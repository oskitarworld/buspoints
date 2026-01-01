import UIKit
import GoogleMaps
import CoreLocation

class StreetViewController: UIViewController {
  private let lat: Double
  private let lng: Double
  private var panoramaView: GMSPanoramaView?

  init(lat: Double, lng: Double) {
    self.lat = lat
    self.lng = lng
    super.init(nibName: nil, bundle: nil)
  }

  required init?(coder aDecoder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  override func viewDidLoad() {
    super.viewDidLoad()
    view.backgroundColor = .black

    panoramaView = GMSPanoramaView(frame: view.bounds)
    panoramaView?.autoresizingMask = [.flexibleWidth, .flexibleHeight]
    if let pv = panoramaView {
      view.addSubview(pv)
      let coord = CLLocationCoordinate2D(latitude: lat, longitude: lng)
      pv.moveNearCoordinate(coord)
    }

    // Close button
    let close = UIButton(type: .system)
    close.translatesAutoresizingMaskIntoConstraints = false
    // Use SF Symbol if available (iOS 13+). Otherwise fallback to text.
    if #available(iOS 13.0, *) {
      let image = UIImage(systemName: "map.fill")
      close.setImage(image, for: .normal)
      close.setTitle("  Volver al mapa", for: .normal)
      close.titleLabel?.font = UIFont.systemFont(ofSize: 14, weight: .semibold)
      close.tintColor = .white
      close.setTitleColor(.white, for: .normal)
      // Pill background with color
      close.backgroundColor = UIColor.systemOrange
      close.layer.cornerRadius = 24
      close.clipsToBounds = true
      close.contentEdgeInsets = UIEdgeInsets(top: 8, left: 12, bottom: 8, right: 12)
    } else {
      // Fallback: emoji + text
      close.setTitle("🗺 Volver al mapa", for: .normal)
      close.setTitleColor(.white, for: .normal)
      close.backgroundColor = UIColor(white: 0.1, alpha: 0.6)
      close.layer.cornerRadius = 6
    }

    close.addTarget(self, action: #selector(closeTapped), for: .touchUpInside)
    view.addSubview(close)
    NSLayoutConstraint.activate([
      close.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 12),
      close.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -12),
      close.heightAnchor.constraint(equalToConstant: 48),
      close.widthAnchor.constraint(greaterThanOrEqualToConstant: 80),
    ])
  }

  @objc func closeTapped() {
    dismiss(animated: true, completion: nil)
  }
}
