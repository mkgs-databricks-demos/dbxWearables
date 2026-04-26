import SwiftUI
import AVFoundation

/// QR code scanner for importing Databricks workspace coordinates and
/// service-principal credentials in a single scan.
///
/// Expected QR code format (JSON). Workspace URL fields are optional — if
/// omitted, the currently-configured workspace stays in place and only the
/// SPN credentials are updated:
/// ```json
/// {
///   "client_id": "abc123-def456-ghi789",
///   "client_secret": "dapi...",
///   "api_base_url": "https://<ws>.databricksapps.com/<app>",
///   "workspace_host": "https://<ws>.cloud.databricks.com",
///   "workspace_label": "Field Eng Demo"
/// }
/// ```
struct QRCodeScannerView: View {
    @Environment(\.dismiss) private var dismiss
    let onScan: (ScanResult) -> Void
    
    @StateObject private var scanner = QRCodeScanner()
    @State private var showError = false
    @State private var errorMessage = ""
    
    var body: some View {
        NavigationStack {
            ZStack {
                // Camera preview
                QRCodeCameraView(scanner: scanner)
                    .ignoresSafeArea()
                
                // Overlay
                VStack {
                    Spacer()
                    
                    // Instructions card
                    VStack(spacing: 12) {
                        HStack(spacing: 12) {
                            Image(systemName: "qrcode.viewfinder")
                                .font(.title)
                                .foregroundStyle(DBXColors.dbxRed)
                            
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Scan QR Code")
                                    .font(.headline)
                                    .foregroundStyle(.white)
                                Text("Position the QR code within the frame")
                                    .font(.caption)
                                    .foregroundStyle(.white.opacity(0.8))
                            }
                        }
                        
                        if scanner.isScanning {
                            ProgressView()
                                .progressViewStyle(.circular)
                                .tint(.white)
                        }
                    }
                    .padding(20)
                    .frame(maxWidth: .infinity)
                    .background(.ultraThinMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .padding(.horizontal)
                    .padding(.bottom, 40)
                }
                
                // Scanning frame overlay
                scanningFrame
            }
            .navigationTitle("Scan Credentials")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .foregroundStyle(.white)
                }
            }
            .toolbarBackground(.hidden, for: .navigationBar)
            .onAppear {
                scanner.startScanning { result in
                    handleScan(result)
                }
            }
            .onDisappear {
                scanner.stopScanning()
            }
            .alert("Scan Error", isPresented: $showError) {
                Button("Try Again", role: .cancel) {
                    scanner.startScanning { result in
                        handleScan(result)
                    }
                }
                Button("Cancel", role: .destructive) {
                    dismiss()
                }
            } message: {
                Text(errorMessage)
            }
        }
    }
    
    private var scanningFrame: some View {
        GeometryReader { geometry in
            let size = min(geometry.size.width, geometry.size.height) * 0.7
            
            ZStack {
                // Dimmed overlay
                Rectangle()
                    .fill(.black.opacity(0.5))
                    .ignoresSafeArea()
                
                // Clear scanning area
                Rectangle()
                    .frame(width: size, height: size)
                    .blendMode(.destinationOut)
                
                // Corner brackets
                VStack {
                    HStack {
                        scanCorner(.topLeft)
                        Spacer()
                        scanCorner(.topRight)
                    }
                    Spacer()
                    HStack {
                        scanCorner(.bottomLeft)
                        Spacer()
                        scanCorner(.bottomRight)
                    }
                }
                .frame(width: size, height: size)
            }
            .compositingGroup()
            .position(x: geometry.size.width / 2, y: geometry.size.height / 2)
        }
    }
    
    private func scanCorner(_ corner: Corner) -> some View {
        let length: CGFloat = 30
        let thickness: CGFloat = 4
        
        return ZStack {
            switch corner {
            case .topLeft:
                VStack(alignment: .leading, spacing: 0) {
                    Rectangle().frame(width: length, height: thickness)
                    HStack(spacing: 0) {
                        Rectangle().frame(width: thickness, height: length - thickness)
                        Spacer()
                    }
                }
            case .topRight:
                VStack(alignment: .trailing, spacing: 0) {
                    Rectangle().frame(width: length, height: thickness)
                    HStack(spacing: 0) {
                        Spacer()
                        Rectangle().frame(width: thickness, height: length - thickness)
                    }
                }
            case .bottomLeft:
                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: 0) {
                        Rectangle().frame(width: thickness, height: length - thickness)
                        Spacer()
                    }
                    Rectangle().frame(width: length, height: thickness)
                }
            case .bottomRight:
                VStack(alignment: .trailing, spacing: 0) {
                    HStack(spacing: 0) {
                        Spacer()
                        Rectangle().frame(width: thickness, height: length - thickness)
                    }
                    Rectangle().frame(width: length, height: thickness)
                }
            }
        }
        .foregroundStyle(DBXColors.dbxRed)
    }
    
    enum Corner {
        case topLeft, topRight, bottomLeft, bottomRight
    }
    
    private func handleScan(_ result: Result<ScanResult, ScanError>) {
        switch result {
        case .success(let scanResult):
            onScan(scanResult)
            dismiss()

        case .failure(let error):
            errorMessage = error.userMessage
            showError = true
        }
    }
}

// MARK: - QR Code Scanner Logic

@MainActor
final class QRCodeScanner: NSObject, ObservableObject {
    @Published var isScanning = false
    
    private var captureSession: AVCaptureSession?
    private var completionHandler: ((Result<ScanResult, ScanError>) -> Void)?
    
    func startScanning(completion: @escaping (Result<ScanResult, ScanError>) -> Void) {
        self.completionHandler = completion
        self.isScanning = true
        
        Task {
            await setupCaptureSession()
        }
    }
    
    func stopScanning() {
        captureSession?.stopRunning()
        captureSession = nil
        isScanning = false
        completionHandler = nil
    }
    
    private func setupCaptureSession() async {
        guard let device = AVCaptureDevice.default(for: .video) else {
            completionHandler?(.failure(.cameraUnavailable))
            return
        }
        
        do {
            let input = try AVCaptureDeviceInput(device: device)
            
            let session = AVCaptureSession()
            session.beginConfiguration()
            
            guard session.canAddInput(input) else {
                completionHandler?(.failure(.invalidSetup))
                return
            }
            session.addInput(input)
            
            let output = AVCaptureMetadataOutput()
            guard session.canAddOutput(output) else {
                completionHandler?(.failure(.invalidSetup))
                return
            }
            session.addOutput(output)
            
            output.setMetadataObjectsDelegate(self, queue: .main)
            output.metadataObjectTypes = [.qr]
            
            session.commitConfiguration()
            
            self.captureSession = session
            
            // Start on background thread
            Task.detached {
                session.startRunning()
            }
        } catch {
            completionHandler?(.failure(.cameraAccessDenied))
        }
    }
    
    func getPreviewLayer() -> AVCaptureVideoPreviewLayer? {
        guard let session = captureSession else { return nil }
        let layer = AVCaptureVideoPreviewLayer(session: session)
        layer.videoGravity = .resizeAspectFill
        return layer
    }
}

// MARK: - Metadata Delegate

extension QRCodeScanner: AVCaptureMetadataOutputObjectsDelegate {
    nonisolated func metadataOutput(
        _ output: AVCaptureMetadataOutput,
        didOutput metadataObjects: [AVMetadataObject],
        from connection: AVCaptureConnection
    ) {
        guard let metadataObject = metadataObjects.first as? AVMetadataMachineReadableCodeObject,
              let stringValue = metadataObject.stringValue else {
            return
        }
        
        Task { @MainActor in
            processQRCode(stringValue)
        }
    }
    
    private func processQRCode(_ code: String) {
        // Stop scanning immediately to prevent multiple scans
        stopScanning()
        
        // Parse JSON
        guard let data = code.data(using: .utf8) else {
            completionHandler?(.failure(.invalidFormat))
            return
        }
        
        do {
            let decoder = JSONDecoder()
            let credentials = try decoder.decode(QRCredentials.self, from: data)

            guard !credentials.client_id.isEmpty else {
                completionHandler?(.failure(.missingClientID))
                return
            }

            guard !credentials.client_secret.isEmpty else {
                completionHandler?(.failure(.missingClientSecret))
                return
            }

            // Workspace URLs are optional. If either is present, both must
            // parse — partial workspace overrides aren't useful and lead to
            // confusing half-switched state.
            var apiBaseURL: URL?
            var workspaceHost: URL?
            if credentials.api_base_url != nil || credentials.workspace_host != nil {
                guard let raw = credentials.api_base_url,
                      let parsed = WorkspaceConfig.validatedURL(from: raw) else {
                    completionHandler?(.failure(.invalidWorkspaceURL))
                    return
                }
                guard let rawHost = credentials.workspace_host,
                      let parsedHost = WorkspaceConfig.validatedURL(from: rawHost) else {
                    completionHandler?(.failure(.invalidWorkspaceURL))
                    return
                }
                apiBaseURL = parsed
                workspaceHost = parsedHost
            }

            completionHandler?(.success(ScanResult(
                clientID: credentials.client_id,
                clientSecret: credentials.client_secret,
                apiBaseURL: apiBaseURL,
                workspaceHost: workspaceHost,
                workspaceLabel: credentials.workspace_label
            )))
        } catch {
            completionHandler?(.failure(.invalidFormat))
        }
    }
}

// MARK: - Camera Preview View

struct QRCodeCameraView: UIViewRepresentable {
    let scanner: QRCodeScanner
    
    func makeUIView(context: Context) -> UIView {
        let view = UIView(frame: .zero)
        view.backgroundColor = .black
        return view
    }
    
    func updateUIView(_ uiView: UIView, context: Context) {
        // Remove existing layers
        uiView.layer.sublayers?.forEach { $0.removeFromSuperlayer() }
        
        // Add preview layer
        if let previewLayer = scanner.getPreviewLayer() {
            previewLayer.frame = uiView.bounds
            uiView.layer.addSublayer(previewLayer)
        }
    }
}

// MARK: - Models

struct QRCredentials: Codable {
    let client_id: String
    let client_secret: String
    let api_base_url: String?
    let workspace_host: String?
    let workspace_label: String?
}

struct ScanResult {
    let clientID: String
    let clientSecret: String
    /// Optional. If present, the scan switches the active workspace.
    let apiBaseURL: URL?
    /// Optional. Always set in tandem with `apiBaseURL`.
    let workspaceHost: URL?
    /// Optional human-readable label (e.g. "Field Eng Demo").
    let workspaceLabel: String?
}

enum ScanError: Error {
    case cameraUnavailable
    case cameraAccessDenied
    case invalidSetup
    case invalidFormat
    case missingClientID
    case missingClientSecret
    case invalidWorkspaceURL

    var userMessage: String {
        switch self {
        case .cameraUnavailable:
            return "Camera is not available on this device."
        case .cameraAccessDenied:
            return "Camera access denied. Please enable camera access in Settings."
        case .invalidSetup:
            return "Failed to setup camera for scanning."
        case .invalidFormat:
            return "Invalid QR code format. Expected JSON with client_id and client_secret."
        case .missingClientID:
            return "QR code is missing client_id field."
        case .missingClientSecret:
            return "QR code is missing client_secret field."
        case .invalidWorkspaceURL:
            return "QR code workspace URLs are invalid. Both api_base_url and workspace_host must be valid http(s) URLs."
        }
    }
}
