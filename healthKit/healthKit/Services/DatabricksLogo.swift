import SwiftUI

/// Displays the Databricks logo from assets
/// Supports both image-based and text-based fallback
struct DatabricksLogo: View {
    var height: CGFloat = 24
    var useWordmark: Bool = true // If false, shows just the brick icon
    var forDarkBackground: Bool = true // Use white text variant for dark backgrounds
    
    var body: some View {
        Group {
            // Choose the right logo variant based on background
            let logoName = useWordmark ? 
                (forDarkBackground ? "databricks-logo-dark" : "databricks-logo-light") :
                "databricks-icon"
            
            // Try to load the logo image from assets
            if UIImage(named: logoName) != nil {
                Image(logoName)
                    .resizable()
                    .renderingMode(.original) // Preserve original colors (orange diamond + text)
                    .aspectRatio(contentMode: .fit)
                    .frame(height: height)
            } else {
                // Fallback to text if image not available
                textFallback
            }
        }
    }
    
    private var textFallback: some View {
        HStack(spacing: 4) {
            // Orange diamond icon fallback
            ZStack {
                Rectangle()
                    .fill(Color(red: 1.0, green: 0.27, blue: 0.13)) // Databricks orange/red
                    .frame(width: height * 0.7, height: height * 0.7)
                    .rotationEffect(.degrees(45))
            }
            .frame(width: height, height: height)
            
            if useWordmark {
                Text("Databricks")
                    .font(.system(size: height * 0.7, weight: .medium, design: .default))
                    .foregroundStyle(forDarkBackground ? .white : .black)
            }
        }
    }
}

/// Legacy wordmark (for compatibility with existing code)
/// Defaults to dark background variant (white text)
struct DatabricksWordmark: View {
    var size: CGFloat = 20

    var body: some View {
        DatabricksLogo(height: size, useWordmark: true, forDarkBackground: true)
    }
}

#Preview("Logo Variants") {
    VStack(spacing: 30) {
        VStack(spacing: 10) {
            Text("On Dark Background")
                .foregroundStyle(.white)
            DatabricksLogo(height: 24, forDarkBackground: true)
            DatabricksLogo(height: 32, forDarkBackground: true)
        }
        .padding()
        .background(.black)
        .cornerRadius(12)
        
        VStack(spacing: 10) {
            Text("On Light Background")
            DatabricksLogo(height: 24, forDarkBackground: false)
            DatabricksLogo(height: 32, forDarkBackground: false)
        }
        .padding()
        .background(.white)
        .cornerRadius(12)
        
        VStack(spacing: 10) {
            Text("Icon Only")
                .foregroundStyle(.white)
            DatabricksLogo(height: 32, useWordmark: false)
        }
        .padding()
        .background(.black)
        .cornerRadius(12)
    }
    .padding()
    .background(Color.gray.opacity(0.3))
}

