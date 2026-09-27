import Lottie
import SwiftUI

struct LottieView: UIViewRepresentable {
    let name: String
    var loopMode: LottieLoopMode = .loop
    var contentMode: UIView.ContentMode = .scaleAspectFit

    func makeUIView(context: Context) -> UIView {
        let container = UIView()
        container.backgroundColor = .clear

        let animationView = LottieAnimationView()
        animationView.translatesAutoresizingMaskIntoConstraints = false
        animationView.animation = LottieAnimation.named(name)
        animationView.loopMode = loopMode
        animationView.contentMode = contentMode
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
        if context.coordinator.currentName != name {
            animationView.animation = LottieAnimation.named(name)
            context.coordinator.currentName = name
        }
        animationView.loopMode = loopMode
        animationView.contentMode = contentMode
        if animationView.isAnimationPlaying == false {
            animationView.play()
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(currentName: name)
    }
}

extension LottieView {
    func loopMode(_ mode: LottieLoopMode) -> Self {
        var copy = self
        copy.loopMode = mode
        return copy
    }
}

extension LottieView {
    final class Coordinator {
        var currentName: String
        weak var animationView: LottieAnimationView?

        init(currentName: String) {
            self.currentName = currentName
        }
    }
}
