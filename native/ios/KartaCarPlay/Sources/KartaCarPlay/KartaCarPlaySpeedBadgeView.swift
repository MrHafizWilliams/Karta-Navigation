#if canImport(UIKit)
import UIKit

/// High-contrast, non-interactive MY / SG / BN Speed-Limit & Live Speedometer HUD
/// anchored cleanly inside `CPWindow`'s unobstructed safe-area corner.
/// Automatically mirrors Obsidian Night and Tropical Daylight vehicle headlight states
/// and scales cleanly across standard, wide, and ultra-wide panoramic dashboards.
public final class KartaCarPlaySpeedBadgeView: UIView {
    private let cardLayer = CALayer()
    private let signContainer = UIView()
    private let signLabel = UILabel()
    private let speedLabel = UILabel()
    private let unitAndCountryLabel = UILabel()

    private var theme: KartaCarPlayTheme = .obsidianNight
    private var currentAlertLevel: String = "normal"

    public override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        setupHierarchy()
        applyTheme(.obsidianNight)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    private func setupHierarchy() {
        layer.cornerRadius = 16
        layer.borderWidth = 1.6
        layer.shadowOffset = CGSize(width: 0, height: 4)
        layer.shadowRadius = 10
        layer.shadowOpacity = 0.28

        // Authentic MY / SG / BN circular speed-limit sign (white core + bold red ring)
        signContainer.translatesAutoresizingMaskIntoConstraints = false
        signContainer.backgroundColor = .white
        signContainer.layer.cornerRadius = 24
        signContainer.layer.borderWidth = 4.2
        addSubview(signContainer)

        signLabel.translatesAutoresizingMaskIntoConstraints = false
        signLabel.textAlignment = .center
        signLabel.font = UIFont.monospacedDigitSystemFont(ofSize: 17, weight: .black)
        signLabel.textColor = UIColor(red: 0x11 / 255.0, green: 0x16 / 255.0, blue: 0x1C / 255.0, alpha: 1.0)
        signLabel.text = "--"
        signContainer.addSubview(signLabel)

        speedLabel.translatesAutoresizingMaskIntoConstraints = false
        speedLabel.font = UIFont.monospacedDigitSystemFont(ofSize: 28, weight: .heavy)
        speedLabel.text = "0"
        addSubview(speedLabel)

        unitAndCountryLabel.translatesAutoresizingMaskIntoConstraints = false
        unitAndCountryLabel.font = UIFont.monospacedSystemFont(ofSize: 10.5, weight: .bold)
        unitAndCountryLabel.text = "km/h · MY"
        addSubview(unitAndCountryLabel)

        NSLayoutConstraint.activate([
            signContainer.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            signContainer.centerYAnchor.constraint(equalTo: centerYAnchor),
            signContainer.widthAnchor.constraint(equalToConstant: 48),
            signContainer.heightAnchor.constraint(equalToConstant: 48),

            signLabel.centerXAnchor.constraint(equalTo: signContainer.centerXAnchor),
            signLabel.centerYAnchor.constraint(equalTo: signContainer.centerYAnchor),

            speedLabel.leadingAnchor.constraint(equalTo: signContainer.trailingAnchor, constant: 10),
            speedLabel.topAnchor.constraint(equalTo: topAnchor, constant: 7),
            speedLabel.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -12),

            unitAndCountryLabel.leadingAnchor.constraint(equalTo: speedLabel.leadingAnchor),
            unitAndCountryLabel.topAnchor.constraint(equalTo: speedLabel.bottomAnchor, constant: -2),
            unitAndCountryLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            unitAndCountryLabel.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -8)
        ])
    }

    public func applyTheme(_ next: KartaCarPlayTheme) {
        theme = next
        updateVisualStyle()
    }

    public func update(frame: KartaCarPlayNavigationFrame, scale: CGFloat) {
        let shouldShow = frame.isNavigating || frame.speedLimitKmh != nil
        isHidden = !shouldShow
        guard shouldShow else { return }

        currentAlertLevel = frame.speedAlertLevel.lowercased()
        signLabel.text = frame.speedLimitKmh.map(String.init) ?? "--"
        speedLabel.text = "\(Int(frame.currentSpeedKmh.rounded()))"
        unitAndCountryLabel.text = "km/h · \(frame.countryCode) \(frame.currencySymbol)"
        transform = CGAffineTransform(scaleX: scale, y: scale)
        updateVisualStyle()
    }

    private func updateVisualStyle() {
        let alertColor: UIColor
        switch currentAlertLevel {
        case "alert":
            alertColor = theme.statusAlert
            backgroundColor = theme.statusAlert.withAlphaComponent(theme.isDarkMode ? 0.28 : 0.16)
            layer.borderColor = theme.statusAlert.cgColor
        case "caution":
            alertColor = theme.statusCaution
            backgroundColor = theme.surfaceCard.withAlphaComponent(0.94)
            layer.borderColor = theme.statusCaution.cgColor
        default:
            alertColor = theme.textPrimary
            backgroundColor = theme.surfaceCard.withAlphaComponent(0.92)
            layer.borderColor = theme.borderSubtle.cgColor
        }

        signContainer.layer.borderColor = theme.statusAlert.cgColor
        speedLabel.textColor = alertColor
        unitAndCountryLabel.textColor = theme.textSecondary
        layer.shadowColor = (theme.isDarkMode ? UIColor.black : theme.textPrimary).cgColor
    }
}
#endif
