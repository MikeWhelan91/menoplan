import Lottie
import SwiftUI

/// The same lightweight Lottie bridge used by Linecheck, kept here so onboarding
/// animations are bundled with Menoplan rather than loaded over the network.
struct MenoLottieView: UIViewRepresentable {
    let name: String
    var loopMode: LottieLoopMode = .loop

    func makeUIView(context: Context) -> UIView {
        let container = UIView()
        container.backgroundColor = .clear

        let animationView = LottieAnimationView()
        animationView.translatesAutoresizingMaskIntoConstraints = false
        animationView.animation = LottieAnimation.named(name)
        animationView.loopMode = loopMode
        animationView.contentMode = .scaleAspectFit
        animationView.backgroundBehavior = .pauseAndRestore
        animationView.play()

        container.addSubview(animationView)
        NSLayoutConstraint.activate([
            animationView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            animationView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            animationView.topAnchor.constraint(equalTo: container.topAnchor),
            animationView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])
        context.coordinator.animationView = animationView
        return container
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        guard let animationView = context.coordinator.animationView else { return }
        if context.coordinator.name != name {
            animationView.animation = LottieAnimation.named(name)
            context.coordinator.name = name
        }
        animationView.loopMode = loopMode
        if !animationView.isAnimationPlaying { animationView.play() }
    }

    func makeCoordinator() -> Coordinator { Coordinator(name: name) }

    final class Coordinator {
        var name: String
        weak var animationView: LottieAnimationView?
        init(name: String) { self.name = name }
    }
}

extension MenoLottieView {
    func loopMode(_ mode: LottieLoopMode) -> Self {
        var copy = self
        copy.loopMode = mode
        return copy
    }
}
