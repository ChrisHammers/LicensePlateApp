//
//  BadgeView.swift
//  LicensePlateApp
//
//  Created for Friends & Family MVP
//

import SwiftUI

struct BadgeView: View {
    let count: Int
    var size: CGFloat = 20
    
    var body: some View {
        if count > 0 {
            Text("\(count)")
                .font(.system(.caption2, design: .rounded))
                .fontWeight(.bold)
                .foregroundColor(.white)
                .frame(minWidth: size, minHeight: size)
                .padding(.horizontal, count > 9 ? 6 : 4)
                .background(
                    Capsule()
                        .fill(Color.red)
                )
        }
    }
}

struct BadgeModifier: ViewModifier {
    let count: Int
    var alignment: Alignment = .topTrailing
    
    func body(content: Content) -> some View {
        content
            .overlay(alignment: alignment) {
                if count > 0 {
                    BadgeView(count: count)
                        .offset(x: 8, y: -8)
                }
            }
    }
}

extension View {
    func badge(count: Int, alignment: Alignment = .topTrailing) -> some View {
        modifier(BadgeModifier(count: count, alignment: alignment))
    }
}

#Preview {
    VStack(spacing: 20) {
        HStack {
            Image(systemName: "bell")
                .font(.title)
                .badge(count: 5)
            
            Image(systemName: "person.2")
                .font(.title)
                .badge(count: 12)
            
            Image(systemName: "house")
                .font(.title)
                .badge(count: 0)
        }
        
        Button("Test Button") {}
            .buttonStyle(.borderedProminent)
            .badge(count: 3)
    }
    .padding()
}

