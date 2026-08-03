//
//  DisperseViewModifier.swift
//  Portado desde DisperseEffect (Balaji Venkatesh).
//

import SwiftUI

enum DisperseDirection: Int, CaseIterable {
    case leftToRight = 0
    case rightToLeft = 1
    case topToBottom = 2
    case bottomToTop = 3
}

extension View {
    /// Partículas Metal que dispersan la vista (eliminar mensaje/foto).
    @ViewBuilder
    func disperseEffect(progress: Double, count: Int, direction: DisperseDirection) -> some View {
        self
            .visualEffect { content, proxy in
                content
                    .layerEffect(
                        ShaderLibrary.disperseEffect(
                            .float2(proxy.size),
                            .float(Float(progress)),
                            .float(Float(count)),
                            .float(Float(direction.rawValue))
                        ),
                        maxSampleOffset: proxy.size
                    )
            }
    }
}
