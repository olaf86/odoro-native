//
//  MotionSourceClipFileStore.swift
//  Odoro
//

import Foundation

private struct MotionSourceClipPayload: Codable, Sendable {
    static let currentSchemaVersion = 1

    var schemaVersion: Int
    var skeletonId: String
    var jointCount: Int
    var captureMode: CaptureMode
    var sourcePlatform: String
    var sourceBackend: String
    var frames: [MotionPayloadFrame]

    init(
        clip: MotionClip,
        captureMode: CaptureMode,
        sourcePlatform: String,
        sourceBackend: String
    ) {
        self.schemaVersion = Self.currentSchemaVersion
        self.skeletonId = MotionSourceClipBinaryCodec.skeletonIdentifier(
            for: captureMode,
            jointCount: clip.frames.first?.jointPositions.count ?? 0
        )
        self.jointCount = clip.frames.first?.jointPositions.count ?? 0
        self.captureMode = captureMode
        self.sourcePlatform = sourcePlatform
        self.sourceBackend = sourceBackend
        self.frames = clip.frames.map { frame in
            let rotations = frame.jointRotations?.count == frame.jointPositions.count
                ? frame.jointRotations?.map { $0.map(MotionPayloadQuaternion.init) }
                : nil
            return MotionPayloadFrame(
                timeSeconds: frame.time,
                timeBeats: 0,
                positions: frame.jointPositions.map(MotionPayloadVector3.init),
                rotations: rotations,
                confidences: nil,
                jointStatuses: nil
            )
        }
    }

    func makeMotionClip() -> MotionClip {
        MotionClip(
            frames: frames.map { frame in
                let rotations = frame.rotations?.count == frame.positions.count
                    ? frame.rotations?.map { $0?.motionValue }
                    : nil
                return MotionFrame(
                    time: frame.timeSeconds,
                    jointPositions: frame.positions.map(\.simdValue),
                    jointRotations: rotations
                )
            }
        )
    }
}

private enum MotionSourceClipBinaryCodec {
    static let magic = Data("OSRC".utf8)
    static let currentSchemaVersion: UInt32 = 2
    static let currentFlags: UInt32 = 0

    enum CodecError: LocalizedError {
        case invalidHeader
        case unsupportedVersion(UInt32)
        case truncatedData
        case invalidCaptureMode(String)
        case invalidUTF8Field
        case invalidFrameLayout

        var errorDescription: String? {
            switch self {
            case .invalidHeader:
                "The source clip file header is invalid."
            case let .unsupportedVersion(version):
                "Unsupported source clip file version: \(version)"
            case .truncatedData:
                "The source clip file ended unexpectedly."
            case let .invalidCaptureMode(rawValue):
                "Unsupported capture mode in source clip: \(rawValue)"
            case .invalidUTF8Field:
                "The source clip file contains invalid UTF-8 metadata."
            case .invalidFrameLayout:
                "The source clip frame layout is invalid."
            }
        }
    }

    static func encode(
        clip: MotionClip,
        captureMode: CaptureMode,
        sourcePlatform: String,
        sourceBackend: String
    ) throws -> Data {
        let jointCount = clip.frames.first?.jointPositions.count ?? 0
        var data = Data()

        data.append(magic)
        data.appendUInt32(currentSchemaVersion)
        data.appendUInt32(currentFlags)
        data.appendUInt32(UInt32(clip.frames.count))
        data.appendUInt32(UInt32(jointCount))
        try data.appendString(captureMode.rawValue)
        try data.appendString(sourcePlatform)
        try data.appendString(sourceBackend)
        try data.appendString(skeletonIdentifier(for: captureMode, jointCount: jointCount))

        let validityByteCount = bitsetByteCount(for: jointCount)

        for frame in clip.frames {
            guard frame.jointPositions.count == jointCount else {
                throw CodecError.invalidFrameLayout
            }

            data.appendFloat64(frame.time)
            for position in frame.jointPositions {
                data.appendFloat32(position.x)
                data.appendFloat32(position.y)
                data.appendFloat32(position.z)
            }

            let rotations = frame.jointRotations
            let hasRotationArray = rotations?.count == jointCount
            data.appendUInt8(hasRotationArray ? 1 : 0)

            guard hasRotationArray, let rotations else {
                continue
            }

            let validity = rotationValidityBitset(for: rotations, byteCount: validityByteCount)
            data.append(validity)

            for rotation in rotations {
                guard let rotation else { continue }
                data.appendFloat32(rotation.ix)
                data.appendFloat32(rotation.iy)
                data.appendFloat32(rotation.iz)
                data.appendFloat32(rotation.r)
            }
        }

        return data
    }

    static func decode(_ data: Data) throws -> MotionClip {
        let isLegacyJSON = data.first == UInt8(ascii: "{")
        if isLegacyJSON {
            return try JSONDecoder().decode(MotionSourceClipPayload.self, from: data).makeMotionClip()
        }

        var reader = DataReader(data: data)
        let magic = try reader.readData(count: Self.magic.count)
        guard magic == Self.magic else {
            throw CodecError.invalidHeader
        }

        let version = try reader.readUInt32()
        guard version == currentSchemaVersion else {
            throw CodecError.unsupportedVersion(version)
        }

        _ = try reader.readUInt32() // flags
        let frameCount = Int(try reader.readUInt32())
        let jointCount = Int(try reader.readUInt32())
        let captureModeRawValue = try reader.readString()
        _ = try reader.readString() // sourcePlatform
        _ = try reader.readString() // sourceBackend
        _ = try reader.readString() // skeletonId

        guard CaptureMode(rawValue: captureModeRawValue) != nil else {
            throw CodecError.invalidCaptureMode(captureModeRawValue)
        }

        let validityByteCount = bitsetByteCount(for: jointCount)
        var frames: [MotionFrame] = []
        frames.reserveCapacity(frameCount)

        for _ in 0..<frameCount {
            let time = try reader.readFloat64()
            var positions: [SIMD3<Float>] = []
            positions.reserveCapacity(jointCount)
            for _ in 0..<jointCount {
                let x = try reader.readFloat32()
                let y = try reader.readFloat32()
                let z = try reader.readFloat32()
                positions.append(SIMD3<Float>(x, y, z))
            }

            let hasRotationArray = try reader.readUInt8() == 1
            let rotations: [MotionJointRotation?]?
            if hasRotationArray {
                let validity = try reader.readData(count: validityByteCount)
                var decodedRotations = Array<MotionJointRotation?>(repeating: nil, count: jointCount)
                for index in 0..<jointCount where validity.bitIsSet(at: index) {
                    let ix = try reader.readFloat32()
                    let iy = try reader.readFloat32()
                    let iz = try reader.readFloat32()
                    let r = try reader.readFloat32()
                    decodedRotations[index] = MotionJointRotation(ix: ix, iy: iy, iz: iz, r: r)
                }
                rotations = decodedRotations
            } else {
                rotations = nil
            }

            frames.append(
                MotionFrame(
                    time: time,
                    jointPositions: positions,
                    jointRotations: rotations
                )
            )
        }

        if !reader.isAtEnd {
            throw CodecError.invalidFrameLayout
        }

        return MotionClip(frames: frames)
    }

    static func skeletonIdentifier(
        for captureMode: CaptureMode,
        jointCount: Int
    ) -> String {
        if captureMode == .rearBody3D {
            return "arkit.body3d"
        }

        if jointCount == OdoroSkeletonDefinition.jointCount {
            return OdoroSkeletonDefinition.id
        }

        return "source.\(captureMode.rawValue)"
    }

    private static func bitsetByteCount(for jointCount: Int) -> Int {
        (jointCount + 7) / 8
    }

    private static func rotationValidityBitset(
        for rotations: [MotionJointRotation?],
        byteCount: Int
    ) -> Data {
        var bytes = Array(repeating: UInt8(0), count: byteCount)
        for (index, rotation) in rotations.enumerated() where rotation != nil {
            bytes[index / 8] |= UInt8(1 << (index % 8))
        }
        return Data(bytes)
    }
}

private struct DataReader {
    enum ReaderError: LocalizedError {
        case truncatedData
        case invalidUTF8Field

        var errorDescription: String? {
            switch self {
            case .truncatedData:
                "The source clip data ended unexpectedly."
            case .invalidUTF8Field:
                "The source clip contains invalid UTF-8 text."
            }
        }
    }

    let data: Data
    var offset: Int = 0

    var isAtEnd: Bool {
        offset == data.count
    }

    mutating func readUInt8() throws -> UInt8 {
        guard offset < data.count else {
            throw ReaderError.truncatedData
        }

        let value = data[offset]
        offset += 1
        return value
    }

    mutating func readUInt32() throws -> UInt32 {
        let size = MemoryLayout<UInt32>.size
        let slice = try readData(count: size)
        return slice.withUnsafeBytes { rawBuffer in
            rawBuffer.load(as: UInt32.self)
        }.littleEndian
    }

    mutating func readFloat32() throws -> Float {
        Float(bitPattern: try readUInt32())
    }

    mutating func readFloat64() throws -> Double {
        let size = MemoryLayout<UInt64>.size
        let slice = try readData(count: size)
        let bits = slice.withUnsafeBytes { rawBuffer in
            rawBuffer.load(as: UInt64.self)
        }.littleEndian
        return Double(bitPattern: bits)
    }

    mutating func readString() throws -> String {
        let byteCount = Int(try readUInt32())
        let bytes = try readData(count: byteCount)
        guard let string = String(data: bytes, encoding: .utf8) else {
            throw ReaderError.invalidUTF8Field
        }
        return string
    }

    mutating func readData(count: Int) throws -> Data {
        guard count >= 0, offset + count <= data.count else {
            throw ReaderError.truncatedData
        }

        let slice = data.subdata(in: offset..<(offset + count))
        offset += count
        return slice
    }
}

struct MotionSourceClipFileStore {
    private let fileManager: FileManager
    private let baseDirectoryURL: URL

    init(fileManager: FileManager = .default, baseDirectoryURL: URL? = nil) {
        self.fileManager = fileManager
        if let baseDirectoryURL {
            self.baseDirectoryURL = baseDirectoryURL
        } else {
            let applicationSupportURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            self.baseDirectoryURL = applicationSupportURL.appending(path: "SourceClips", directoryHint: .isDirectory)
        }
    }

    func sourceClipURL(for takeID: UUID) -> URL {
        baseDirectoryURL.appending(path: "\(takeID.uuidString).odoro.source", directoryHint: .notDirectory)
    }

    @discardableResult
    func write(
        _ clip: MotionClip?,
        for takeID: UUID,
        captureMode: CaptureMode,
        sourceBackend: String
    ) throws -> URL? {
        guard let clip else {
            return nil
        }

        try ensureBaseDirectoryExists()
        let sourceClipURL = sourceClipURL(for: takeID)
        let data = try MotionSourceClipBinaryCodec.encode(
            clip: clip,
            captureMode: captureMode,
            sourcePlatform: "iOS",
            sourceBackend: sourceBackend
        )
        try data.write(to: sourceClipURL, options: .atomic)
        return sourceClipURL
    }

    func read(for takeID: UUID) throws -> MotionClip? {
        let sourceClipURL = sourceClipURL(for: takeID)
        guard fileManager.fileExists(atPath: sourceClipURL.path()) else {
            return nil
        }

        let data = try Data(contentsOf: sourceClipURL)
        return try MotionSourceClipBinaryCodec.decode(data)
    }

    func removeSourceClip(for takeID: UUID) throws {
        let sourceClipURL = sourceClipURL(for: takeID)
        guard fileManager.fileExists(atPath: sourceClipURL.path()) else {
            return
        }

        try fileManager.removeItem(at: sourceClipURL)
    }

    private func ensureBaseDirectoryExists() throws {
        guard !fileManager.fileExists(atPath: baseDirectoryURL.path()) else {
            return
        }

        try fileManager.createDirectory(at: baseDirectoryURL, withIntermediateDirectories: true)
    }
}

private extension Data {
    mutating func appendUInt8(_ value: UInt8) {
        append(value)
    }

    mutating func appendUInt32(_ value: UInt32) {
        var littleEndianValue = value.littleEndian
        Swift.withUnsafeBytes(of: &littleEndianValue) { bytes in
            append(bytes.bindMemory(to: UInt8.self))
        }
    }

    mutating func appendFloat32(_ value: Float) {
        appendUInt32(value.bitPattern)
    }

    mutating func appendFloat64(_ value: Double) {
        var littleEndianValue = value.bitPattern.littleEndian
        Swift.withUnsafeBytes(of: &littleEndianValue) { bytes in
            append(bytes.bindMemory(to: UInt8.self))
        }
    }

    mutating func appendString(_ value: String) throws {
        guard let encoded = value.data(using: .utf8) else {
            throw MotionSourceClipBinaryCodec.CodecError.invalidUTF8Field
        }
        appendUInt32(UInt32(encoded.count))
        append(encoded)
    }

    func bitIsSet(at index: Int) -> Bool {
        let byteIndex = index / 8
        guard indices.contains(byteIndex) else {
            return false
        }
        let mask = UInt8(1 << (index % 8))
        return self[byteIndex] & mask != 0
    }
}
