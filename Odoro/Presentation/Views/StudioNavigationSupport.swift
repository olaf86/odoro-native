//
//  StudioNavigationSupport.swift
//  Odoro
//

import SwiftUI

extension StudioScreenTransition {
    var transition: AnyTransition {
        switch self {
        case .fromLeading:
            .asymmetric(insertion: .move(edge: .leading), removal: .move(edge: .trailing))
        case .fromTrailing:
            .asymmetric(insertion: .move(edge: .trailing), removal: .move(edge: .leading))
        case .fromTop:
            .asymmetric(insertion: .move(edge: .top), removal: .move(edge: .bottom))
        case .fromBottom:
            .asymmetric(insertion: .move(edge: .bottom), removal: .move(edge: .top))
        }
    }
}

enum SwipeReturnDirection {
    case left
    case right
    case up
}

struct SwipeBackEdgeZone: View {
    let direction: SwipeReturnDirection
    let action: () -> Void

    var body: some View {
        Color.clear
            .contentShape(Rectangle())
            .frame(
                maxWidth: direction == .up ? .infinity : nil,
                maxHeight: direction == .left || direction == .right ? .infinity : nil
            )
            .frame(
                width: direction == .left || direction == .right ? 28 : nil,
                height: direction == .up ? 34 : nil
            )
            .safeAreaPadding(edgeForDirection, direction == .up ? 8 : 0)
            .gesture(
                DragGesture(minimumDistance: 28, coordinateSpace: .local)
                    .onEnded { value in
                        switch direction {
                        case .left:
                            if value.translation.width < -70,
                               abs(value.translation.width) > abs(value.translation.height) {
                                action()
                            }
                        case .right:
                            if value.translation.width > 70,
                               abs(value.translation.width) > abs(value.translation.height) {
                                action()
                            }
                        case .up:
                            if value.translation.height < -70,
                               abs(value.translation.height) > abs(value.translation.width) {
                                action()
                            }
                        }
                    }
            )
    }

    private var edgeForDirection: Edge.Set {
        switch direction {
        case .left:
            .trailing
        case .right:
            .leading
        case .up:
            .bottom
        }
    }
}
