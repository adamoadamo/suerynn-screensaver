import ScreenSaver
import AppKit

@objc(SuerynnSaverView)
class MainView: ScreenSaverView {
    private class ImageCacheManager {
        static let shared = ImageCacheManager()
        private var imageCache: [String: NSImage] = [:]
        private let bundle = Bundle(for: MainView.self)

        func loadImage(named name: String) -> NSImage? {
            if let cachedImage = imageCache[name] {
                return cachedImage
            }

            guard let imagePath = bundle.path(forResource: name, ofType: "png"),
                  let image = NSImage(contentsOfFile: imagePath) else {
                NSLog("Suerynn Saver: failed to load image \(name)")
                return nil
            }

            imageCache[name] = image
            return image
        }
    }

    private let imageCache = ImageCacheManager.shared
    private struct Character {
        var position: CGPoint
        var edge: Int       // 0 = bottom, 1 = right, 2 = top, 3 = left
        var angle: CGFloat
        var images: [NSImage]
        var currentFrame: Int = 0
        var frameDelayCounter: Int = 0
        var state: MovementState = .movingAlongEdge
        var opacity: CGFloat = 1.0
        var characterType: String  // Store which character this is
    }

    private enum MovementState {
        case movingAlongEdge
        case movingAlongCorner(arcCenter: CGPoint, endAngle: CGFloat, currentAngle: CGFloat, angleIncrement: CGFloat)
    }

    private var characters: [Character] = []
    private var charactersInitialized = false

    // Movement and sprite timing are counted in steps; the constants below were tuned at 60 steps per second.
    private let stepInterval: TimeInterval = 1.0 / 60.0

    // Define percentages as constants
    private struct ScreenPercentages {
        static let characterSize: CGFloat = 0.275      // 27.5% of smaller screen dimension
        static let cornerRadius: CGFloat = 0.225       // 22.5% of smaller screen dimension
        static let edgeOffset: CGFloat = -0.0045       // -0.45% of smaller screen dimension
        static let minDistance: CGFloat = 0.45         // 45% of smaller screen dimension between spawn points
        static let edgeSpeed: CGFloat = 0.0015         // 0.15% of smaller screen dimension per step
        static let cornerSpeedMultiplier: CGFloat = 5.5  // Multiplier for corner speed relative to edge speed
        static let frameDelay: Int = 7                 // Number of steps to wait before advancing animation
    }

    // Computed properties based on screen size
    private var smallerScreenDimension: CGFloat {
        return min(bounds.width, bounds.height)
    }

    private var squareSize: CGFloat {
        return smallerScreenDimension * ScreenPercentages.characterSize
    }

    private var imageSize: CGFloat {
        return squareSize * 1.05  // Slightly larger than square size
    }

    private var cornerRadius: CGFloat {
        return smallerScreenDimension * ScreenPercentages.cornerRadius
    }

    private var edgeOffset: CGFloat {
        return smallerScreenDimension * ScreenPercentages.edgeOffset
    }

    private var minDistance: CGFloat {
        return smallerScreenDimension * ScreenPercentages.minDistance
    }

    private var edgeSpeed: CGFloat {
        return smallerScreenDimension * ScreenPercentages.edgeSpeed
    }

    private var cornerSpeed: CGFloat {
        return edgeSpeed * ScreenPercentages.cornerSpeedMultiplier
    }

    // Add frameDelay as a computed property
    private var frameDelay: Int {
        return ScreenPercentages.frameDelay
    }

    // Rename from 'animations' to 'characterAnimations'
    private let characterAnimations: [String: [String]] = [
        "Apple": ["Apple_Walk-1", "Apple_Walk-2", "Apple_Walk-3"],
        "Butterfly": ["Butterfly_Walk-1", "Butterfly_Walk-2", "Butterfly_Walk-3", "Butterfly_Walk-4", "Butterfly_Walk-5", "Butterfly_Walk-6", "Butterfly_Walk-7", "Butterfly_Walk-8"],
        "Man": ["Man_Walk-1", "Man_Walk-2", "Man_Walk-3"],
        "Paper": ["Paper_Walk-1", "Paper_Walk-2", "Paper_Walk-3"],
        "Peanut": ["Peanut_Walk-1", "Peanut_Walk-2", "Peanut_Walk-3"],
        "Can": ["Can_Walk-1", "Can_Walk-2", "Can_Walk-3"],
        "Lip": ["Lip_Walk-1", "Lip_Walk-2", "Lip_Walk-3"],
        "Bird": ["Bird_Walk-1", "Bird_Walk-2", "Bird_Walk-3", "Bird_Walk-4", "Bird_Walk-5", "Bird_Walk-6", "Bird_Walk-7"],
        "Pea": ["Pea_Walk-1", "Pea_Walk-2", "Pea_Walk-3"],
        "Cry": ["Cry_Walk-1", "Cry_Walk-2", "Cry_Walk-3"],
        "Elephant": ["Elephant_Walk-1", "Elephant_Walk-2", "Elephant_Walk-3"],
        "Goo": ["Goo_Walk-1", "Goo_Walk-2", "Goo_Walk-3"],
        "Balloon": ["Balloon_Walk-1", "Balloon_Walk-2", "Balloon_Walk-3"],
        "Pant": ["Pant_Walk-1", "Pant_Walk-2", "Pant_Walk-3"],
        "Bat": ["Bat_Walk-1", "Bat_Walk-2", "Bat_Walk-3", "Bat_Walk-4", "Bat_Walk-5", "Bat_Walk-6"],
        "Horse": ["Horse_Walk-1", "Horse_Walk-2", "Horse_Walk-3"],
        "Umbrella": ["Umbrella_Walk-1", "Umbrella_Walk-2", "Umbrella_Walk-3"],
        "Roll": ["Roll_Walk-1", "Roll_Walk-2", "Roll_Walk-3"],
        "Paint": ["Paint_Walk-1", "Paint_Walk-2", "Paint_Walk-3", "Paint_Walk-4"],
    ]

    private let maxActiveCharacters = 7
    private var availableCharacterTypes: Set<String> = []
    private var pendingCharacterTypes: [String] = []  // Chosen to join, waiting for a free spot
    private var fadeTimer: Timer?
    private let fadeInterval: TimeInterval = 20  // Seconds between character swaps

    @objc override init?(frame: NSRect, isPreview: Bool) {
        super.init(frame: frame, isPreview: isPreview)
        commonInit()
    }

    @objc required init?(coder: NSCoder) {
        super.init(coder: coder)
        commonInit()
    }

    private func commonInit() {
        animationTimeInterval = stepInterval
        loadImages()

        // On macOS 14+ the screen saver host can keep views alive (and animating) after the
        // screen saver is dismissed, so stop explicitly when the system says it is stopping.
        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(screenSaverWillStop(_:)),
            name: NSNotification.Name("com.apple.screensaver.willstop"),
            object: nil
        )
    }

    deinit {
        DistributedNotificationCenter.default().removeObserver(self)
        fadeTimer?.invalidate()
    }

    @objc private func screenSaverWillStop(_ notification: Notification) {
        if !isPreview {
            stopAnimation()
        }
    }

    override func startAnimation() {
        super.startAnimation()
        setupFadeTimer()
    }

    override func stopAnimation() {
        super.stopAnimation()
        fadeTimer?.invalidate()
        fadeTimer = nil
    }

    private func loadImages() {
        characters = []
        availableCharacterTypes = Set(characterAnimations.keys)

        // Randomly select initial characters
        let initialCharacters = Array(characterAnimations.keys).shuffled().prefix(maxActiveCharacters)

        for characterName in initialCharacters {
            if let frames = characterAnimations[characterName] {
                let images = frames.compactMap { imageCache.loadImage(named: $0) }

                if !images.isEmpty {
                    characters.append(Character(
                        position: .zero,  // Position will be set by setupCharacters
                        edge: 0,
                        angle: 0,
                        images: images,
                        opacity: 0.0,  // Start fully transparent
                        characterType: characterName
                    ))
                    availableCharacterTypes.remove(characterName)
                }
            }
        }
    }

    private func setupFadeTimer() {
        guard fadeTimer == nil else { return }
        fadeTimer = Timer.scheduledTimer(withTimeInterval: fadeInterval, repeats: true) { [weak self] _ in
            self?.rotateRandomCharacter()
        }
    }

    private func rotateRandomCharacter() {
        // Don't select characters that are currently fading
        guard let characterToRemove = characters.filter({ $0.opacity == 1.0 }).randomElement(),
              !availableCharacterTypes.isEmpty else {
            return
        }

        // Get list of available characters excluding the one being removed
        let validNewTypes = availableCharacterTypes.filter { $0 != characterToRemove.characterType }
        guard let newCharacterType = validNewTypes.randomElement() else {
            return
        }

        // Reserve the newcomer so a later swap can't pick it too
        availableCharacterTypes.remove(newCharacterType)

        startFadeAnimation(for: characterToRemove.characterType, fadingIn: false) { [weak self] in
            guard let self = self else { return }

            // Remove the character from the array after fade out
            if let index = self.characters.firstIndex(where: { $0.characterType == characterToRemove.characterType }) {
                self.characters.remove(at: index)
            }

            self.availableCharacterTypes.insert(characterToRemove.characterType)

            let delay = TimeInterval.random(in: 2...4)
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                self?.pendingCharacterTypes.append(newCharacterType)
            }
        }
    }

    private func startFadeAnimation(for characterType: String, fadingIn: Bool, completion: (() -> Void)? = nil) {
        let duration: TimeInterval = 0.5
        let steps = 30
        let stepDuration = duration / Double(steps)
        var currentStep = 0

        Timer.scheduledTimer(withTimeInterval: stepDuration, repeats: true) { [weak self] timer in
            guard let self = self else {
                timer.invalidate()
                return
            }

            currentStep += 1

            guard let index = self.characters.firstIndex(where: { $0.characterType == characterType }) else {
                timer.invalidate()
                return
            }

            if fadingIn {
                self.characters[index].opacity = min(CGFloat(currentStep) / CGFloat(steps), 1.0)
            } else {
                self.characters[index].opacity = max(1.0 - (CGFloat(currentStep) / CGFloat(steps)), 0.0)
            }
            self.needsDisplay = true

            if currentStep >= steps {
                timer.invalidate()
                completion?()
            }
        }
    }

    override func draw(_ rect: NSRect) {
        super.draw(rect)

        for character in characters {
            drawCharacter(character)
        }
    }

    private func drawCharacter(_ character: Character) {
        guard let context = NSGraphicsContext.current?.cgContext,
              character.images.indices.contains(character.currentFrame) else { return }

        context.saveGState()

        // Move to position and rotate
        context.translateBy(x: character.position.x, y: character.position.y)
        context.rotate(by: character.angle)

        let image = character.images[character.currentFrame]
        let rect = CGRect(x: -imageSize / 2, y: 0, width: imageSize, height: imageSize)
        image.draw(in: rect, from: .zero, operation: .sourceOver, fraction: character.opacity)

        context.restoreGState()
    }

    override func animateOneFrame() {
        guard bounds.width > 0 && bounds.height > 0 else { return }

        if !charactersInitialized {
            setupCharacters()
        }

        if !pendingCharacterTypes.isEmpty {
            let pending = pendingCharacterTypes
            pendingCharacterTypes = pending.filter { !addNewCharacter(ofType: $0) }
        }

        for i in 0..<characters.count {
            animateCharacter(&characters[i])
            moveCharacter(&characters[i])
        }
        needsDisplay = true
    }

    override func setFrameSize(_ newSize: NSSize) {
        let sizeChanged = newSize != frame.size
        super.setFrameSize(newSize)

        // Characters are laid out for a particular screen size; re-place them if it changes.
        if sizeChanged && charactersInitialized && newSize.width > 0 && newSize.height > 0 {
            placeCharacters()
        }
    }

    private func animateCharacter(_ character: inout Character) {
        character.frameDelayCounter += 1
        if character.frameDelayCounter >= frameDelay {
            character.currentFrame = (character.currentFrame + 1) % character.images.count
            character.frameDelayCounter = 0
        }
    }

    private func moveCharacter(_ character: inout Character) {
        switch character.state {
        case .movingAlongEdge:
            switch character.edge {
            case 0: // Bottom edge
                character.position.x += edgeSpeed
                character.angle = 0
                if character.position.x >= bounds.width - cornerRadius - edgeOffset {
                    // Start turning along bottom-right corner
                    let arcCenter = CGPoint(
                        x: bounds.width - cornerRadius - edgeOffset,
                        y: cornerRadius + edgeOffset
                    )
                    let startAngle: CGFloat = 3 * CGFloat.pi / 2
                    let endAngle: CGFloat = 2 * CGFloat.pi
                    let angleIncrement = computeAngleIncrement(startAngle: startAngle, endAngle: endAngle, speed: cornerSpeed)
                    character.state = .movingAlongCorner(
                        arcCenter: arcCenter,
                        endAngle: endAngle,
                        currentAngle: startAngle,
                        angleIncrement: angleIncrement
                    )
                }
            case 1: // Right edge
                character.position.y += edgeSpeed
                character.angle = CGFloat.pi / 2
                if character.position.y >= bounds.height - cornerRadius - edgeOffset {
                    // Start turning along top-right corner
                    let arcCenter = CGPoint(
                        x: bounds.width - cornerRadius - edgeOffset,
                        y: bounds.height - cornerRadius - edgeOffset
                    )
                    let startAngle: CGFloat = 0
                    let endAngle: CGFloat = CGFloat.pi / 2
                    let angleIncrement = computeAngleIncrement(startAngle: startAngle, endAngle: endAngle, speed: cornerSpeed)
                    character.state = .movingAlongCorner(
                        arcCenter: arcCenter,
                        endAngle: endAngle,
                        currentAngle: startAngle,
                        angleIncrement: angleIncrement
                    )
                }
            case 2: // Top edge
                character.position.x -= edgeSpeed
                character.angle = CGFloat.pi
                if character.position.x <= cornerRadius + edgeOffset {
                    // Start turning along top-left corner
                    let arcCenter = CGPoint(
                        x: cornerRadius + edgeOffset,
                        y: bounds.height - cornerRadius - edgeOffset
                    )
                    let startAngle: CGFloat = CGFloat.pi / 2
                    let endAngle: CGFloat = CGFloat.pi
                    let angleIncrement = computeAngleIncrement(startAngle: startAngle, endAngle: endAngle, speed: cornerSpeed)
                    character.state = .movingAlongCorner(
                        arcCenter: arcCenter,
                        endAngle: endAngle,
                        currentAngle: startAngle,
                        angleIncrement: angleIncrement
                    )
                }
            case 3: // Left edge
                character.position.y -= edgeSpeed
                character.angle = 3 * CGFloat.pi / 2
                if character.position.y <= cornerRadius + edgeOffset {
                    // Start turning along bottom-left corner
                    let arcCenter = CGPoint(
                        x: cornerRadius + edgeOffset,
                        y: cornerRadius + edgeOffset
                    )
                    let startAngle: CGFloat = CGFloat.pi
                    let endAngle: CGFloat = 3 * CGFloat.pi / 2
                    let angleIncrement = computeAngleIncrement(startAngle: startAngle, endAngle: endAngle, speed: cornerSpeed)
                    character.state = .movingAlongCorner(
                        arcCenter: arcCenter,
                        endAngle: endAngle,
                        currentAngle: startAngle,
                        angleIncrement: angleIncrement
                    )
                }
            default:
                break
            }

        case .movingAlongCorner(let arcCenter, let endAngle, var currentAngle, let angleIncrement):
            // Adjust angleIncrement to prevent overshooting
            let remainingAngle = endAngle - currentAngle
            let direction: CGFloat = angleIncrement >= 0 ? 1 : -1
            let absIncrement = abs(angleIncrement)
            let absRemaining = abs(remainingAngle)
            let adjustedIncrement = absIncrement > absRemaining ? direction * absRemaining : angleIncrement
            currentAngle += adjustedIncrement

            let finishedTurning = (angleIncrement >= 0 && currentAngle >= endAngle) || (angleIncrement < 0 && currentAngle <= endAngle)

            if finishedTurning {
                currentAngle = endAngle
                character.state = .movingAlongEdge
                character.edge = (character.edge + 1) % 4
                character.angle = angleForEdge(character.edge) // Set angle based on new edge
                // Set position exactly at the end angle
                character.position.x = arcCenter.x + cornerRadius * cos(currentAngle)
                character.position.y = arcCenter.y + cornerRadius * sin(currentAngle)
            } else {
                // Update the character's state with the new currentAngle
                character.state = .movingAlongCorner(
                    arcCenter: arcCenter,
                    endAngle: endAngle,
                    currentAngle: currentAngle,
                    angleIncrement: angleIncrement
                )
                character.position.x = arcCenter.x + cornerRadius * cos(currentAngle)
                character.position.y = arcCenter.y + cornerRadius * sin(currentAngle)
                character.angle = normalizeAngle(angle: currentAngle + CGFloat.pi / 2)
            }
        }
    }

    private func computeAngleIncrement(startAngle: CGFloat, endAngle: CGFloat, speed: CGFloat) -> CGFloat {
        let angleDifference = endAngle - startAngle
        let direction: CGFloat = angleDifference >= 0 ? 1 : -1
        return direction * speed / cornerRadius
    }

    private func normalizeAngle(angle: CGFloat) -> CGFloat {
        var newAngle = angle.truncatingRemainder(dividingBy: 2 * CGFloat.pi)
        if newAngle < 0 {
            newAngle += 2 * CGFloat.pi
        }
        return newAngle
    }

    private func angleForEdge(_ edge: Int) -> CGFloat {
        switch edge {
        case 0:
            return 0.0 // Bottom edge
        case 1:
            return CGFloat.pi / 2 // Right edge
        case 2:
            return CGFloat.pi // Top edge
        case 3:
            return 3 * CGFloat.pi / 2 // Left edge
        default:
            return 0.0
        }
    }

    private func setupCharacters() {
        placeCharacters()
        charactersInitialized = true

        // Stagger the fade-ins
        for (index, character) in characters.enumerated() {
            let characterType = character.characterType
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(index) * 0.75) { [weak self] in
                self?.startFadeAnimation(for: characterType, fadingIn: true)
            }
        }
    }

    private func placeCharacters() {
        let startPositions = generateNonOverlappingPositions(screenWidth: bounds.width, screenHeight: bounds.height)

        for (index, start) in startPositions.enumerated() where index < characters.count {
            characters[index].position = start.position
            characters[index].edge = start.edge
            characters[index].angle = start.angle
            characters[index].state = .movingAlongEdge
        }
    }

    private func randomEdgePosition(screenWidth: CGFloat, screenHeight: CGFloat) -> (position: CGPoint, edge: Int, angle: CGFloat) {
        let offset = edgeOffset  // Use the same offset calculation as movement
        let edge = Int.random(in: 0...3)

        switch edge {
        case 0: // Bottom edge
            return (CGPoint(x: CGFloat.random(in: 0...screenWidth), y: offset), edge, 0)
        case 1: // Right edge
            return (CGPoint(x: screenWidth - offset, y: CGFloat.random(in: 0...screenHeight)), edge, CGFloat.pi / 2)
        case 2: // Top edge
            return (CGPoint(x: CGFloat.random(in: 0...screenWidth), y: screenHeight - offset), edge, CGFloat.pi)
        default: // Left edge
            return (CGPoint(x: offset, y: CGFloat.random(in: 0...screenHeight)), edge, 3 * CGFloat.pi / 2)
        }
    }

    private func generateNonOverlappingPositions(screenWidth: CGFloat, screenHeight: CGFloat) -> [(position: CGPoint, edge: Int, angle: CGFloat)] {
        var positions: [(position: CGPoint, edge: Int, angle: CGFloat)] = []

        for _ in 0..<characters.count {
            var candidate = randomEdgePosition(screenWidth: screenWidth, screenHeight: screenHeight)
            var attempts = 1

            // Check minimum distance from other characters; after 100 tries, use the last position generated
            while attempts <= 100 && positions.contains(where: { hypot(candidate.position.x - $0.position.x, candidate.position.y - $0.position.y) < minDistance }) {
                candidate = randomEdgePosition(screenWidth: screenWidth, screenHeight: screenHeight)
                attempts += 1
            }

            positions.append(candidate)
        }

        return positions
    }

    /// Adds a character of the given type at a free spot on the edge.
    /// Returns false if no spot is free right now, so the caller can try again on a later frame.
    private func addNewCharacter(ofType type: String) -> Bool {
        guard let frames = characterAnimations[type] else { return true }

        let images = frames.compactMap { imageCache.loadImage(named: $0) }
        guard !images.isEmpty else { return true }

        // Generate a new position ensuring no overlap, with a buffer zone around the minimum distance
        let safeDistance = minDistance * 1.1
        let maxAttempts = 200

        for _ in 0..<maxAttempts {
            let candidate = randomEdgePosition(screenWidth: bounds.width, screenHeight: bounds.height)
            let overlaps = characters.contains { existingCharacter in
                hypot(candidate.position.x - existingCharacter.position.x,
                      candidate.position.y - existingCharacter.position.y) < safeDistance
            }

            if !overlaps {
                characters.append(Character(
                    position: candidate.position,
                    edge: candidate.edge,
                    angle: candidate.angle,
                    images: images,
                    opacity: 0.0,
                    characterType: type
                ))
                startFadeAnimation(for: type, fadingIn: true)
                return true
            }
        }

        // No gap is wide enough right now. The spacing shifts as characters round the corners,
        // so a later frame will find one rather than leaving the screen a character short.
        return false
    }
}
