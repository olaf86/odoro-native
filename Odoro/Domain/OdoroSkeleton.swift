//
//  OdoroSkeleton.swift
//  Odoro
//

import Foundation

enum OdoroJointName: String, CaseIterable, Codable, Sendable {
    case root
    case head
    case nose
    case leftShoulder
    case rightShoulder
    case leftElbow
    case rightElbow
    case leftWrist
    case rightWrist
    case leftHip
    case rightHip
    case leftKnee
    case rightKnee
    case leftAnkle
    case rightAnkle
    case leftFoot
    case rightFoot
}

enum OdoroJointStatus: String, Codable, Sendable {
    case observed
    case mapped
    case derived
    case inferred
    case missing
}

enum OdoroSkeletonDefinition {
    nonisolated static let id = "odoro.body.v1"
    nonisolated static let jointNames = OdoroJointName.allCases
    nonisolated static let jointCount = jointNames.count

    nonisolated static func index(of jointName: OdoroJointName) -> Int {
        jointNames.firstIndex(of: jointName)!
    }
}
