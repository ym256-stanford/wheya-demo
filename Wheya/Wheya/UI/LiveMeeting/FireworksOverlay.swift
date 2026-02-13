//
//  FireworksOverlay.swift
//  Wheya
//
//  Created by Yuliia Murakami on 9/15/25.
//

import SwiftUI

struct FireworksOverlay: View {
    @Binding var isVisible: Bool
    @State private var bursts: [Burst] = []
    @State private var lastUpdate = Date()

    var body: some View {
        GeometryReader { geo in
            TimelineView(.animation) { timeline in
                Canvas { context, size in
                    // Draw all live particles
                    for burst in bursts {
                        for p in burst.particles {
                            let r = CGRect(
                                x: p.position.x - p.size/2,
                                y: p.position.y - p.size/2,
                                width: p.size, height: p.size
                            )
                            context.fill(
                                Path(ellipseIn: r),
                                with: .color(p.color.opacity(p.alpha))
                            )
                        }
                    }
                }
                .background(Color.black.opacity(0.15))    // subtle dim
                .ignoresSafeArea()
                .onChange(of: timeline.date) { oldDate, newDate in
                    let dt = min(0.033, max(0, newDate.timeIntervalSince(oldDate)))
                    step(dt, in: geo.size)
                    cullDead()
                }
                .onAppear {
                    lastUpdate = timeline.date
                    // Spawn 3–4 bursts at random spots
                    for i in 0..<4 {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15 * Double(i)) {
                            spawnBurst(in: geo.size)
                        }
                    }
                }
            }
        }
    }

    // MARK: Particle engine

    private let gravity: CGFloat = 220.0

    private func spawnBurst(in size: CGSize) {
        let center = CGPoint(x: CGFloat.random(in: size.width*0.2...size.width*0.8),
                             y: CGFloat.random(in: size.height*0.2...size.height*0.45))
        var particles: [Particle] = []
        let n = 80
        for i in 0..<n {
            let angle = (Double(i) / Double(n)) * .pi * 2 + Double.random(in: -0.15...0.15)
            let speed = CGFloat.random(in: 120...260)
            let vx = cos(angle) * speed
            let vy = sin(angle) * speed
            let size = CGFloat.random(in: 3.5...6.5)
            let life = CGFloat.random(in: 0.9...1.4)
            let color = palette.randomElement()!
            particles.append(Particle(position: center,
                                      velocity: CGVector(dx: vx, dy: vy),
                                      life: life, age: 0, size: size, color: color))
        }
        bursts.append(Burst(particles: particles))
    }

    private func step(_ dt: TimeInterval, in canvas: CGSize) {
        for i in bursts.indices {
            for j in bursts[i].particles.indices {
                var p = bursts[i].particles[j]
                // physics
                p.velocity.dy += gravity * CGFloat(dt)
                p.position.x += p.velocity.dx * CGFloat(dt)
                p.position.y += p.velocity.dy * CGFloat(dt)
                p.age += CGFloat(dt)
                // fade + shrink
                let t = min(1, p.age / p.life)
                p.alpha = 1 - t
                p.size *= (0.995)
                bursts[i].particles[j] = p
            }
        }
    }

    private func cullDead() {
        bursts.removeAll { burst in
            burst.particles.allSatisfy { $0.age >= $0.life || $0.alpha <= 0.02 }
        }
    }

    private var palette: [Color] {
        [.red, .orange, .yellow, .green, .mint, .teal, .blue, .purple, .pink]
    }

    // MARK: Models

    private struct Burst: Identifiable {
        var id = UUID()
        var particles: [Particle]
    }

    private struct Particle {
        var position: CGPoint
        var velocity: CGVector
        var life: CGFloat
        var age: CGFloat
        var size: CGFloat
        var color: Color
        var alpha: CGFloat = 1
    }
}
