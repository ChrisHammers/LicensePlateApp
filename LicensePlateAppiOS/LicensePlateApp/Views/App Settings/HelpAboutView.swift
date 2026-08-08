//
//  HelpAboutView.swift
//  LicensePlateApp
//
//  Created by Christopher Hammers on 11/11/25.
//

import GoogleMaps
import SwiftUI
import UIKit

struct HelpAboutView: View {
    @Environment(\.dismiss) private var dismiss
    
    @State private var showAbout = false
    @State private var showAcknowledgements = false
    @State private var showFAQ = false
    @State private var showTerms = false
    @State private var showPrivacy = false
    
    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "x.x"
    }
    
    private var appBuild: String {
        return Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"
    }
    
    private var appVersionAndBuild: String {
        return "\(appVersion) (\(appBuild))"
    }
    
    var body: some View {
        AppBackgroundView {
            List {
                    Section {
                        VStack(spacing: 12) {
                            SettingNavigationRow(
                                title: "About".localized,
                                description: "Learn about RoadTrip Royale and HammersTechLLC".localized,
                                icon: "info.circle.fill"
                            ) {
                                showAbout = true
                            }
                          
                            Divider()
                            
                            SettingNavigationRow(
                                title: "Acknowledgements".localized,
                                description: "Open source libraries and SDKs we use".localized,
                                icon: "doc.text.fill"
                            ) {
                                showAcknowledgements = true
                            }
                          
                            Divider()
                            
                            SettingNavigationRow(
                                title: "FAQ".localized,
                                description: "Frequently asked questions".localized,
                                icon: "questionmark.bubble.fill"
                            ) {
                                showFAQ = true
                            }
                          
                            Divider()
                            
                            Button {
                                sendEmail(to: "support@roadtriproyale.com", subject: "RoadTrip Royale Bug Report")
                            } label: {
                                HStack(spacing: 16) {
                                    Image(systemName: "ladybug")
                                        .font(.system(size: 20))
                                        .foregroundStyle(Color.Theme.primaryBlue)
                                        .frame(width: 24)
                                        .accessibilityHidden(true)
                                    
                                    VStack(alignment: .leading, spacing: 6) {
                                        Text("Report a Bug".localized)
                                            .font(.system(.body, design: .rounded))
                                            .fontWeight(.semibold)
                                            .foregroundStyle(Color.Theme.primaryBlue)
                                        
                                        Text("Help us improve by reporting issues".localized)
                                            .font(.system(.caption, design: .rounded))
                                            .foregroundStyle(Color.Theme.softBrown)
                                    }
                                    
                                    Spacer()
                                }
                                .padding(.vertical, 12)
                                .padding(.horizontal, 16)
                                .background(
                                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                                        .fill(Color.Theme.cardBackground)
                                )
                            }
                            .buttonStyle(.plain)
                            .listRowInsets(EdgeInsets(top: 8, leading: 20, bottom: 8, trailing: 20))
                            .accessibilityLabel("Report a Bug".localized)
                            .accessibilityHint("Opens email to report a bug".localized)
                            .accessibilityAddTraits(.isButton)
                            
                            Divider()
                            
                            Button {
                                sendEmail(to: "support@roadtriproyale.com", subject: "RoadTrip Royale Feature Suggestion")
                            } label: {
                                HStack(spacing: 16) {
                                    Image(systemName: "lightbulb")
                                        .font(.system(size: 20))
                                        .foregroundStyle(Color.Theme.primaryBlue)
                                        .frame(width: 24)
                                        .accessibilityHidden(true)
                                    
                                    VStack(alignment: .leading, spacing: 6) {
                                        Text("Suggest a Feature".localized)
                                            .font(.system(.body, design: .rounded))
                                            .fontWeight(.semibold)
                                            .foregroundStyle(Color.Theme.primaryBlue)
                                        
                                        Text("Share your ideas for new features".localized)
                                            .font(.system(.caption, design: .rounded))
                                            .foregroundStyle(Color.Theme.softBrown)
                                    }
                                    
                                    Spacer()
                                }
                                .padding(.vertical, 12)
                                .padding(.horizontal, 16)
                                .background(
                                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                                        .fill(Color.Theme.cardBackground)
                                )
                            }
                            .buttonStyle(.plain)
                            .listRowInsets(EdgeInsets(top: 8, leading: 20, bottom: 8, trailing: 20))
                            .accessibilityLabel("Suggest a Feature".localized)
                            .accessibilityHint("Opens email to suggest a new feature".localized)
                            .accessibilityAddTraits(.isButton)
                            
                            Divider()
                            
                            Button {
                                openRateApp()
                            } label: {
                                HStack(spacing: 16) {
                                    Image(systemName: "star.fill")
                                        .font(.system(size: 20))
                                        .foregroundStyle(Color.Theme.primaryBlue)
                                        .frame(width: 24)
                                        .accessibilityHidden(true)
                                    
                                    VStack(alignment: .leading, spacing: 6) {
                                        Text("Rate RoadTrip Royale".localized)
                                            .font(.system(.body, design: .rounded))
                                            .fontWeight(.semibold)
                                            .foregroundStyle(Color.Theme.primaryBlue)
                                        
                                        Text("Share your App Store review".localized)
                                            .font(.system(.caption, design: .rounded))
                                            .foregroundStyle(Color.Theme.softBrown)
                                    }
                                    
                                    Spacer()
                                }
                                .padding(.vertical, 12)
                                .padding(.horizontal, 16)
                                .background(
                                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                                        .fill(Color.Theme.cardBackground)
                                )
                            }
                            .buttonStyle(.plain)
                            .listRowInsets(EdgeInsets(top: 8, leading: 20, bottom: 8, trailing: 20))
                            .accessibilityLabel("Rate RoadTrip Royale".localized)
                            .accessibilityHint("Opens the App Store so you can leave a review".localized)
                            .accessibilityAddTraits(.isButton)
                            
                            Divider()
                            
                            Button {
                                sendEmail(to: "support@roadtriproyale.com", subject: "RoadTrip Royale Support Issue")
                            } label: {
                                HStack(spacing: 16) {
                                    Image(systemName: "envelope")
                                        .font(.system(size: 20))
                                        .foregroundStyle(Color.Theme.primaryBlue)
                                        .frame(width: 24)
                                        .accessibilityHidden(true)
                                    
                                    VStack(alignment: .leading, spacing: 6) {
                                        Text("Contact Support".localized)
                                            .font(.system(.body, design: .rounded))
                                            .fontWeight(.semibold)
                                            .foregroundStyle(Color.Theme.primaryBlue)
                                        
                                        Text("Get help with the app".localized)
                                            .font(.system(.caption, design: .rounded))
                                            .foregroundStyle(Color.Theme.softBrown)
                                    }
                                    
                                    Spacer()
                                }
                                .padding(.vertical, 12)
                                .padding(.horizontal, 16)
                                .background(
                                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                                        .fill(Color.Theme.cardBackground)
                                )
                            }
                            .buttonStyle(.plain)
                            .listRowInsets(EdgeInsets(top: 8, leading: 20, bottom: 8, trailing: 20))
                            .accessibilityLabel("Contact Support".localized)
                            .accessibilityHint("Opens email to contact support".localized)
                            .accessibilityAddTraits(.isButton)
                            
                            Divider()
                            
                            // App Version and Legal
                            VStack(spacing: 12) {
                                Text("RoadTrip Royale - App Version - %@".localized(appVersionAndBuild))
                                    .font(.system(.caption, design: .rounded))
                                    .foregroundStyle(Color.Theme.softBrown)
                                
                                HStack(spacing: 20) {
                                    // Terms button - isolated tap area
                                    Text("Terms".localized)
                                        .font(.system(.caption, design: .rounded))
                                        .foregroundStyle(Color.Theme.primaryBlue)
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 6)
                                        .contentShape(Rectangle())
                                        .onTapGesture {
                                            showTerms = true
                                        }
                                        .accessibilityLabel("Terms of Use".localized)
                                        .accessibilityHint("Opens Terms of Use".localized)
                                        .accessibilityAddTraits(.isButton)
                                    
                                    Text("·")
                                        .font(.system(.caption, design: .rounded))
                                        .foregroundStyle(Color.Theme.softBrown)
                                        .allowsHitTesting(false)
                                        .accessibilityHidden(true)
                                    
                                    // Privacy button - isolated tap area
                                    Text("Privacy".localized)
                                        .font(.system(.caption, design: .rounded))
                                        .foregroundStyle(Color.Theme.primaryBlue)
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 6)
                                        .contentShape(Rectangle())
                                        .onTapGesture {
                                            showPrivacy = true
                                        }
                                        .accessibilityLabel("Privacy Policy".localized)
                                        .accessibilityHint("Opens Privacy Policy".localized)
                                        .accessibilityAddTraits(.isButton)
                                }
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .listRowInsets(EdgeInsets(top: 8, leading: 20, bottom: 8, trailing: 20))
                            .listRowSeparator(.hidden)
                            .contentShape(Rectangle())
                            .allowsHitTesting(true)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 16)
                        .background(Color.Theme.cardBackground)
                        .cornerRadius(20)
                        .listRowInsets(EdgeInsets(top: 8, leading: 20, bottom: 8, trailing: 20))
                        .listRowBackground(Color.clear)
                    }
                    .textCase(nil)
                }
                .listStyle(.insetGrouped)
                .scrollContentBackground(.hidden)
            }
            .navigationTitle("Help & About".localized)
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarBackButtonHidden(true)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done".localized) {
                        dismiss()
                    }
                    .font(.system(.body, design: .rounded))
                    .fontWeight(.semibold)
                    .foregroundStyle(Color.Theme.primaryBlue)
                    .accessibilityLabel("Done".localized)
                    .accessibilityHint("Closes this view".localized)
                }
            }
            .navigationDestination(isPresented: $showAbout) {
                AboutView()
            }
            .navigationDestination(isPresented: $showAcknowledgements) {
                AcknowledgementsView()
            }
            .navigationDestination(isPresented: $showFAQ) {
                FAQView()
            }
            .navigationDestination(isPresented: $showTerms) {
                TermsView()
            }
            .navigationDestination(isPresented: $showPrivacy) {
                PrivacyView()
            }
        }
    
    
    private func sendEmail(to email: String, subject: String) {
        let encodedSubject = subject.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? subject
        if let url = URL(string: "mailto:\(email)?subject=\(encodedSubject)") {
            UIApplication.shared.open(url)
        }
    }

    /// Prefer App Store write-review URL when an Apple ID is configured (Info.plist or update-policy store URL).
    /// Otherwise fall back to the system review prompt so the control still does something pre-listing.
    private func openRateApp() {
        let storeURLString = AppUpdatePolicy.parse(json: RemoteConfigService.shared.appUpdatePolicyJSON)?
            .ios?
            .storeUrl
        if let url = AppStoreLinks.writeReviewURL(storeURLString: storeURLString) {
            AnalyticsService.shared.log(.reviewLinkOpened(source: "help_about", method: "app_store"))
            UIApplication.shared.open(url)
            return
        }
        AnalyticsService.shared.log(.reviewLinkOpened(source: "help_about", method: "system_prompt"))
        StoreKitReviewPromptPresenter().requestReview()
    }
}

// MARK: - Help & About Sub-Views

struct AboutView: View {
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        AppBackgroundView {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text("RoadTrip Royale".localized)
                        .font(.system(.largeTitle, design: .rounded))
                        .fontWeight(.bold)
                        .foregroundStyle(Color.Theme.primaryBlue)
                    
                    Text("About the App".localized)
                        .font(.system(.title2, design: .rounded))
                        .fontWeight(.semibold)
                        .foregroundStyle(Color.Theme.primaryBlue)
                    
                    Text("RoadTrip Royale is a fun and engaging license plate tracking game that lets you collect license plates from across the United States, Canada, and Mexico during your road trips. Spot plates, track your progress, and see your collection grow on an interactive map!".localized)
                        .font(.system(.body, design: .rounded))
                        .foregroundStyle(Color.Theme.softBrown)
                    
                    Text("About HammersTechLLC".localized)
                        .font(.system(.title2, design: .rounded))
                        .fontWeight(.semibold)
                        .foregroundStyle(Color.Theme.primaryBlue)
                        .padding(.top)
                    
                    Text("RoadTrip Royale is developed by HammersTechLLC, a software development company dedicated to creating innovative and user-friendly mobile applications. We're passionate about building apps that make everyday activities more enjoyable and engaging.".localized)
                        .font(.system(.body, design: .rounded))
                        .foregroundStyle(Color.Theme.softBrown)
                    
                    Text("Contact".localized)
                        .font(.system(.title3, design: .rounded))
                        .fontWeight(.semibold)
                        .foregroundStyle(Color.Theme.primaryBlue)
                        .padding(.top)
                    
                    Text("Email: support@roadtriproyale.com".localized)
                        .font(.system(.body, design: .rounded))
                        .foregroundStyle(Color.Theme.softBrown)
                }
                .padding()
            }
        }
        .navigationTitle("About".localized)
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Done".localized) {
                    dismiss()
                }
                .font(.system(.body, design: .rounded))
                .fontWeight(.semibold)
                .foregroundStyle(Color.Theme.primaryBlue)
            }
        }
    }
}

struct AcknowledgementsView: View {
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        AppBackgroundView {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text("Acknowledgements".localized)
                        .font(.system(.largeTitle, design: .rounded))
                        .fontWeight(.bold)
                        .foregroundStyle(Color.Theme.primaryBlue)
                    
                    Text("RoadTrip Royale uses the following libraries, SDKs, and data sources:".localized)
                        .font(.system(.body, design: .rounded))
                        .foregroundStyle(Color.Theme.softBrown)
                    
                    VStack(alignment: .leading, spacing: 16) {
                        GoogleMapsAcknowledgementItem()
                        
                        AcknowledgementItem(
                            name: "Simplemaps".localized,
                            description: "Administrative boundary data for US states, Canadian provinces, and Mexican states.".localized,
                            url: "https://simplemaps.com"
                        )
                        
                        AcknowledgementItem(
                            name: "Natural Earth".localized,
                            description: "Public-domain country boundary data used for map context.".localized,
                            url: "https://www.naturalearthdata.com"
                        )
                        
                        AcknowledgementItem(
                            name: "Firebase".localized,
                            description: "Backend services including Authentication, Firestore, Storage, and Analytics".localized,
                            url: "https://firebase.google.com"
                        )
                        
                        AcknowledgementItem(
                            name: "Google Sign-In".localized,
                            description: "OAuth authentication for Google accounts".localized,
                            url: "https://developers.google.com/identity/sign-in/ios"
                        )
                        
                        AcknowledgementItem(
                            name: "RevenueCat".localized,
                            description: "In-app purchases and subscription management; see RevenueCat privacy policy.".localized,
                            url: "https://www.revenuecat.com/privacy"
                        )
                        
                        AcknowledgementItem(
                            name: "Google Mobile Ads (AdMob)".localized,
                            description: "Banner advertising in the app; see Google Mobile Ads privacy policy.".localized,
                            url: "https://policies.google.com/technologies/ads"
                        )
                        
                        AcknowledgementItem(
                            name: "Apple Authentication Services".localized,
                            description: "Sign in with Apple integration".localized,
                            url: "https://developer.apple.com/sign-in-with-apple/"
                        )
                        
                        AcknowledgementItem(
                            name: "SwiftUI".localized,
                            description: "Apple's declarative UI framework".localized,
                            url: "https://developer.apple.com/xcode/swiftui/"
                        )
                        
                        AcknowledgementItem(
                            name: "SwiftData".localized,
                            description: "Apple's data persistence framework".localized,
                            url: "https://developer.apple.com/documentation/swiftdata"
                        )
                        
                        AcknowledgementItem(
                            name: "MapKit".localized,
                            description: "Apple's mapping and location services".localized,
                            url: "https://developer.apple.com/mapkit/"
                        )
                        
                        AcknowledgementItem(
                            name: "Speech Framework".localized,
                            description: "Apple's speech recognition framework".localized,
                            url: "https://developer.apple.com/documentation/speech"
                        )
                    }
                }
                .padding()
            }
        }
        .navigationTitle("Acknowledgements".localized)
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Done".localized) {
                    dismiss()
                }
                .font(.system(.body, design: .rounded))
                .fontWeight(.semibold)
                .foregroundStyle(Color.Theme.primaryBlue)
            }
        }
    }
}

private struct GoogleMapsAcknowledgementItem: View {
    @State private var isLicenseExpanded = false
    @State private var licenseText: String?
    @State private var isLoadingLicense = false
    
    private var openSourceLicensesLabel: String {
        "Open-source licenses".localized
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Google Maps SDK".localized)
                .font(.system(.headline, design: .rounded))
                .fontWeight(.semibold)
                .foregroundStyle(Color.Theme.primaryBlue)
            
            Text("Maps and location display for trip tracking and region visualization.".localized)
                .font(.system(.body, design: .rounded))
                .foregroundStyle(Color.Theme.softBrown)
            
            DisclosureGroup(
                isExpanded: $isLicenseExpanded
            ) {
                Group {
                    if let licenseText {
                        GoogleMapsLicenseTextView(text: licenseText)
                            .frame(maxWidth: .infinity)
                            .frame(height: 280)
                            .accessibilityLabel("Google Maps SDK open-source licenses".localized)
                    } else {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .accessibilityLabel("Loading".localized)
                    }
                }
                .padding(.top, 4)
            } label: {
                Text(openSourceLicensesLabel)
                    .font(.system(.subheadline, design: .rounded))
                    .fontWeight(.semibold)
                    .foregroundStyle(Color.Theme.primaryBlue)
                    .accessibilityHint(
                        isLicenseExpanded
                            ? "Collapses Google Maps open-source license text".localized
                            : "Expands Google Maps open-source license text".localized
                    )
            }
            .animation(nil, value: isLicenseExpanded)
            .onChange(of: isLicenseExpanded) { _, expanded in
                guard expanded else { return }
                loadLicenseTextIfNeeded()
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.Theme.cardBackground)
        )
    }
    
    private func loadLicenseTextIfNeeded() {
        guard licenseText == nil, !isLoadingLicense else { return }
        isLoadingLicense = true
        // Yield so the disclosure can paint a spinner before the large string/UITextView attach.
        // GMSServices must be used on the main thread.
        Task { @MainActor in
            await Task.yield()
            licenseText = GMSServices.openSourceLicenseInfo()
            isLoadingLicense = false
        }
    }
}

/// UIKit text view — SwiftUI `Text` chokes on the Maps SDK license dump.
private struct GoogleMapsLicenseTextView: UIViewRepresentable {
    let text: String
    
    func makeUIView(context: Context) -> UITextView {
        let textView = UITextView()
        textView.isEditable = false
        textView.isSelectable = true
        textView.backgroundColor = .clear
        textView.textContainerInset = UIEdgeInsets(top: 0, left: 0, bottom: 0, right: 0)
        textView.textContainer.lineFragmentPadding = 0
        textView.alwaysBounceVertical = true
        textView.font = UIFont.monospacedSystemFont(
            ofSize: UIFont.preferredFont(forTextStyle: .caption1).pointSize,
            weight: .regular
        )
        textView.adjustsFontForContentSizeCategory = true
        textView.textColor = UIColor(Color.Theme.softBrown)
        textView.text = text
        return textView
    }
    
    func updateUIView(_ textView: UITextView, context: Context) {
        if textView.text != text {
            textView.text = text
        }
    }
}

private struct AcknowledgementItem: View {
    let name: String
    let description: String
    let url: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(name)
                .font(.system(.headline, design: .rounded))
                .fontWeight(.semibold)
                .foregroundStyle(Color.Theme.primaryBlue)
            
            Text(description)
                .font(.system(.body, design: .rounded))
                .foregroundStyle(Color.Theme.softBrown)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.Theme.cardBackground)
        )
    }
}

struct FAQView: View {
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        AppBackgroundView {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                Text("Frequently Asked Questions".localized)
                    .font(.system(.largeTitle, design: .rounded))
                    .fontWeight(.bold)
                    .foregroundStyle(Color.Theme.primaryBlue)
                
                FAQItem(
                    question: "How do I play RoadTrip Royale?".localized,
                    answer: "RoadTrip Royale is a license plate tracking game! During your road trips, keep an eye out for license plates from different states, provinces, or regions. When you spot one, use the app to mark it as found. You can use the List tab to manually select plates, or the Voice tab to speak the state/province name. Track your progress and see your collection grow on the interactive map!".localized
                )
                
                FAQItem(
                    question: "How do I create a trip?".localized,
                    answer: "On the main screen, tap the 'Create Trip' button. You can give your trip a custom name, or leave it blank to use the date and time automatically. Once created, tap on the trip to start tracking license plates!".localized
                )
                
                FAQItem(
                    question: "How does the Voice feature work?".localized,
                    answer: "Tap the Voice tab, then press the microphone button. Speak the name of the state or province you see (e.g., 'California' or 'Ontario'). The app will listen and try to match what you said to a valid license plate region. If a match is found, you'll be asked to confirm before adding it to your collection.".localized
                )
                
                FAQItem(
                    question: "Can I track plates from multiple countries?".localized,
                    answer: "Yes! RoadTrip Royale supports license plates from the United States, Canada, and Mexico. The map will automatically switch to show the correct country as you scroll through the list of regions.".localized
                )
                
                FAQItem(
                    question: "How do I see my progress?".localized,
                    answer: "Each trip and each individual game has its own map and summary. On the trip or game screen, summary chips show how many plates you've found and how many remain. The map highlights found regions in yellow — tap it for a full-screen view.".localized
                )
                
                FAQItem(
                    question: "Can I share my trips with others?".localized,
                    answer: "Yes! You can invite friends to play with you on a trip, and after the trip is complete you can share the journey. Trips are stored both on your device and online when you're signed in, so you can keep playing offline and stay in sync when you reconnect.".localized
                )
                
                FAQItem(
                    question: "Do I need an internet connection?".localized,
                    answer: "RoadTrip Royale works offline! You can create trips and track license plates without an internet connection. If you sign in with an account, your data will sync to the cloud when you're online.".localized
                )
                }
                .padding()
            }
        }
        .navigationTitle("FAQ".localized)
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Done".localized) {
                    dismiss()
                }
                .font(.system(.body, design: .rounded))
                .fontWeight(.semibold)
                .foregroundStyle(Color.Theme.primaryBlue)
            }
        }
    }
}

private struct FAQItem: View {
    let question: String
    let answer: String
    @State private var isExpanded = false
    
    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            Text(answer)
                .font(.system(.body, design: .rounded))
                .foregroundStyle(Color.Theme.softBrown)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 8)
                .multilineTextAlignment(.leading)
        } label: {
            Text(question)
                .font(.system(.headline, design: .rounded))
                .fontWeight(.semibold)
                .foregroundStyle(Color.Theme.primaryBlue)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .tint(Color.Theme.primaryBlue)
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.Theme.cardBackground)
        )
        .accessibilityHint(
            isExpanded
                ? "Collapses the answer".localized
                : "Expands the answer".localized
        )
    }
}

struct TermsView: View {
    @Environment(\.dismiss) private var dismiss

    private struct TermsSection: Identifiable {
        var id: String { title }
        let title: String
        let body: String
    }

    private var sections: [TermsSection] {
        [
            TermsSection(
                title: "1. Acceptance of These Terms".localized,
                body: "These Terms of Service (“Terms”) are a binding agreement between you and HammersTech LLC (“HammersTech”, “we”, “us”) governing your use of the RoadTrip Royale app and related services (the “Service”). By downloading, accessing, or using the Service, you agree to these Terms and acknowledge our Privacy Policy. If you do not agree, do not use the Service.".localized
            ),
            TermsSection(
                title: "2. Eligibility and Age Requirements".localized,
                body: "You must be at least 13 years old, or the minimum age of digital consent in your jurisdiction if higher, to accept these Terms yourself. If you are under that age, a parent or legal guardian must accept these Terms on your behalf and supervise your use of the Service. Parents and guardians are responsible for the activity of children playing through their family group or devices.".localized
            ),
            TermsSection(
                title: "3. Safe Driving Comes First".localized,
                body: "RoadTrip Royale is designed for passengers — never for drivers. You agree to never interact with the app while operating a vehicle, to always follow traffic laws, and to use the app only when it is safe to do so. You are solely responsible for your conduct on the road, and HammersTech is not responsible for accidents, violations, or injuries arising from unsafe or unlawful use of the Service.".localized
            ),
            TermsSection(
                title: "4. Your Account".localized,
                body: "You can play as a guest without an account, or register an account to protect your progress and sync it across devices. Guest progress is stored on your device and may be lost if the app is deleted before you register. You are responsible for keeping your credentials secure and for all activity under your account. We may require you to change account or profile names that are offensive, misleading, or infringing.".localized
            ),
            TermsSection(
                title: "5. License to Use the App".localized,
                body: "HammersTech grants you a limited, personal, non-exclusive, non-transferable, revocable license to install and use the app on devices you own or control, for personal, non-commercial entertainment. You may not copy, modify, distribute, sell, lease, or reverse engineer the Service, or create derivative works from it, except to the extent applicable law expressly permits. The Service — including its software, artwork, game design, characters, logos, audio, and text — belongs to HammersTech or its licensors and is protected by intellectual property laws. All rights not expressly granted are reserved.".localized
            ),
            TermsSection(
                title: "6. Fair Play".localized,
                body: "RoadTrip Royale rewards honest, real-world play. You agree not to cheat, spoof or falsify GPS or location data, use bots, automation, or modified versions of the app, exploit bugs, manipulate scores or duplicate detection, or disrupt other players’ games. We may remove or adjust discoveries, XP, achievements, ranks, or other progress that we determine to be illegitimate. Our decisions about competitive integrity are final.".localized
            ),
            TermsSection(
                title: "7. Location Services and GPS Accuracy".localized,
                body: "Some features use your device’s location, including optional background location during active trips. You control location permissions in your device settings, and some features may be limited or unavailable without them. GPS is inherently imprecise: positions, routes, and discoveries may be inaccurate, delayed, or unavailable, and we do not guarantee the accuracy of location-based gameplay.".localized
            ),
            TermsSection(
                title: "8. Your Content".localized,
                body: "You keep ownership of the content you submit to the Service, such as profile names, trip names, and shared trip summaries. You grant HammersTech a non-exclusive, worldwide, royalty-free license to host, store, reproduce, display, and distribute that content solely to operate and improve the Service. We will not sell your content on a standalone basis. You confirm you have the rights to what you submit. We may remove or refuse content or names that are unlawful, offensive, infringing, or otherwise inappropriate. To report content or conduct, email support@roadtriproyale.com.".localized
            ),
            TermsSection(
                title: "9. Multiplayer, Family, and Conduct".localized,
                body: "Multiplayer and Friends & Family features let you play with people you invite. Treat other players with respect. Do not harass, threaten, or impersonate anyone, misuse invitations or share codes, or intentionally disrupt other players’ trips. Parents and guardians who create or manage a family group are responsible for choosing its members, managing its settings, and supervising children’s participation.".localized
            ),
            TermsSection(
                title: "10. Virtual Items and Progression".localized,
                body: "XP, ranks, achievements, avatars, and other virtual items are licensed to you, not sold. They have no monetary value, cannot be redeemed for cash, and are not transferable. As part of operating a live game, we may modify, rebalance, rotate, retire, or discontinue virtual items, seasonal content, and progression systems at any time.".localized
            ),
            TermsSection(
                title: "11. Purchases, Subscriptions, and Ads".localized,
                body: "Subscriptions and other purchases are processed by the app store through which you download the app (currently the Apple App Store). Subscriptions renew automatically until you cancel them in your app store account settings; cancellation takes effect at the end of the current billing period. Refunds are handled by the app store under its policies. Prices and offerings may change for future billing periods. Free play may be supported by advertising.".localized
            ),
            TermsSection(
                title: "12. Third-Party Services".localized,
                body: "The Service relies on third-party services with their own terms and privacy policies, including Firebase and Google Analytics for Firebase (Google), RevenueCat (purchases), and Google AdMob (advertising). Your mobile carrier’s rates and terms apply when you use the Service over a cellular connection, including any roaming charges.".localized
            ),
            TermsSection(
                title: "13. Offline Play and Sync".localized,
                body: "The Service is designed to work offline during trips. Progress made offline is reconciled when your device reconnects, which can take time and can adjust results — for example, when duplicate or conflicting discoveries are resolved. Temporary differences between devices or players during sync are a normal part of the Service.".localized
            ),
            TermsSection(
                title: "14. Updates and Changes to the Service".localized,
                body: "We may add, change, or remove features, rebalance gameplay, fix exploits, and update the app over time. Some updates are required to keep playing, and outdated versions may stop working. We do not promise that any particular feature will remain available, and we may suspend or discontinue all or part of the Service.".localized
            ),
            TermsSection(
                title: "15. Suspension and Termination".localized,
                body: "We may suspend or terminate your access if you materially breach these Terms — including cheating, abuse of other players, or unlawful activity — or where necessary to protect the Service, our players, or our legal obligations. For serious violations we may act immediately; otherwise we will give notice and a reasonable opportunity to fix the problem where practical. You may stop using the Service and delete your account at any time. On termination, your license ends and access to virtual items and progression is lost, without refund except where required by law or by the applicable app store’s policies.".localized
            ),
            TermsSection(
                title: "16. Disclaimers".localized,
                body: "The Service is provided “as is” and “as available”. To the fullest extent permitted by law, we disclaim all warranties, express or implied, including merchantability, fitness for a particular purpose, and non-infringement. We do not warrant uninterrupted or error-free operation, the accuracy of GPS or game data, or compatibility with every device. Some jurisdictions do not allow certain exclusions, so parts of this section may not apply to you.".localized
            ),
            TermsSection(
                title: "17. Limitation of Liability".localized,
                body: "To the fullest extent permitted by law, HammersTech will not be liable for indirect, incidental, special, consequential, punitive, or exemplary damages, or for lost profits, data, or goodwill. Our total liability for all claims relating to the Service will not exceed the greater of the amount you paid us in the 12 months before the claim or fifty U.S. dollars. Nothing in these Terms limits liability for death or personal injury caused by negligence, for fraud, or for anything else that cannot be excluded by law, and nothing limits non-waivable consumer rights.".localized
            ),
            TermsSection(
                title: "18. Indemnification".localized,
                body: "To the extent permitted by the laws of your jurisdiction, you agree to indemnify and hold harmless HammersTech and its officers, employees, and agents from claims, damages, and expenses (including reasonable attorneys’ fees) arising from your breach of these Terms, the content you submit, or your intentional misuse of the Service. This does not apply to the extent a claim arises from our own negligence or breach.".localized
            ),
            TermsSection(
                title: "19. App Store and Platform Terms".localized,
                body: "If you downloaded the app from the Apple App Store, these Terms are between you and HammersTech, not Apple. Apple has no obligation to provide maintenance or support for the app, and is not responsible for warranties, product claims, third-party intellectual property claims, or legal compliance relating to the app. If the app fails to conform to an applicable warranty, you may notify Apple for a refund of any purchase price; Apple has no other warranty obligations. Apple and its subsidiaries are third-party beneficiaries of these Terms and may enforce them. If the app becomes available through other platforms, such as Google Play, these Terms are likewise between you and HammersTech, not the platform provider, and the platform provider is not responsible for the app or its content. You represent that you are not located in a country subject to a U.S. government embargo and are not on any U.S. government list of prohibited or restricted parties.".localized
            ),
            TermsSection(
                title: "20. Governing Law and Disputes".localized,
                body: "These Terms are governed by the laws of the State of Connecticut, United States, excluding its conflict-of-law rules. Disputes will be resolved in the state or federal courts located in Connecticut, and you and HammersTech consent to their jurisdiction. If you live in a jurisdiction — including Canada or Mexico — whose mandatory consumer protection laws give you additional rights, or the right to bring proceedings in your local courts, nothing in this section takes those rights away.".localized
            ),
            TermsSection(
                title: "21. General Terms".localized,
                body: "If any provision of these Terms is found unenforceable, it will be modified to the minimum extent necessary and the rest will remain in effect. Our failure to enforce a provision is not a waiver. You may not assign these Terms; we may assign them as part of a merger, acquisition, or sale of assets. These Terms, together with the Privacy Policy, are the entire agreement between you and HammersTech about the Service.".localized
            ),
            TermsSection(
                title: "22. Changes to These Terms".localized,
                body: "We may update these Terms from time to time. If we make material changes, we will notify you through the app or by other reasonable means before they take effect, and we will update the date at the top of this page. Continued use of the Service after changes take effect means you accept the updated Terms. Previous versions are available on request.".localized
            ),
            TermsSection(
                title: "23. Contact Us".localized,
                body: "Questions about these Terms? Contact HammersTech LLC at support@roadtriproyale.com.".localized
            ),
        ]
    }

    var body: some View {
        AppBackgroundView {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text("Terms of Service".localized)
                        .font(.system(.largeTitle, design: .rounded))
                        .fontWeight(.bold)
                        .foregroundStyle(Color.Theme.primaryBlue)
                        .accessibilityAddTraits(.isHeader)

                    Text("Last updated: August 8, 2026".localized)
                        .font(.system(.caption, design: .rounded))
                        .foregroundStyle(Color.Theme.softBrown)

                    ForEach(sections) { section in
                        Text(section.title)
                            .font(.system(.headline, design: .rounded))
                            .fontWeight(.semibold)
                            .foregroundStyle(Color.Theme.primaryBlue)
                            .padding(.top)
                            .accessibilityAddTraits(.isHeader)

                        Text(section.body)
                            .font(.system(.body, design: .rounded))
                            .foregroundStyle(Color.Theme.softBrown)
                    }
                }
                .padding()
            }
        }
        .navigationTitle("Terms of Service".localized)
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Done".localized) {
                    dismiss()
                }
                .font(.system(.body, design: .rounded))
                .fontWeight(.semibold)
                .foregroundStyle(Color.Theme.primaryBlue)
            }
        }
    }
}

struct PrivacyView: View {
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        AppBackgroundView {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                Text("Privacy Policy".localized)
                    .font(.system(.largeTitle, design: .rounded))
                    .fontWeight(.bold)
                    .foregroundStyle(Color.Theme.primaryBlue)
                
                Text("Last Updated: %@".localized(Date().formatted(date: .abbreviated, time: .omitted)))
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(Color.Theme.softBrown)
                
                Text("1. Information We Collect".localized)
                    .font(.system(.headline, design: .rounded))
                    .fontWeight(.semibold)
                    .foregroundStyle(Color.Theme.primaryBlue)
                    .padding(.top)
                
                Text("RoadTrip Royale collects the following information:\n\n• Account information (username, email) if you create an account\n• Trip data and license plate tracking information\n• Location data (optional, with your permission)\n• Device information for app functionality".localized)
                    .font(.system(.body, design: .rounded))
                    .foregroundStyle(Color.Theme.softBrown)
                
                Text("2. How We Use Your Information".localized)
                    .font(.system(.headline, design: .rounded))
                    .fontWeight(.semibold)
                    .foregroundStyle(Color.Theme.primaryBlue)
                    .padding(.top)
                
                Text("We use your information to:\n\n• Provide and improve the app's functionality\n• Sync your data across devices (if you sign in)\n• Respond to support requests\n• Ensure app security and prevent fraud".localized)
                    .font(.system(.body, design: .rounded))
                    .foregroundStyle(Color.Theme.softBrown)
                
                Text("3. Data Storage".localized)
                    .font(.system(.headline, design: .rounded))
                    .fontWeight(.semibold)
                    .foregroundStyle(Color.Theme.primaryBlue)
                    .padding(.top)
                
                Text("Your data is stored locally on your device. If you sign in with an account, your data is also stored securely in Firebase (Google Cloud Platform) to enable syncing across devices.".localized)
                    .font(.system(.body, design: .rounded))
                    .foregroundStyle(Color.Theme.softBrown)
                
                Text("4. Third-Party Services".localized)
                    .font(.system(.headline, design: .rounded))
                    .fontWeight(.semibold)
                    .foregroundStyle(Color.Theme.primaryBlue)
                    .padding(.top)
                
                Text("Firebase and RevenueCat privacy disclosure".localized)
                    .font(.system(.body, design: .rounded))
                    .foregroundStyle(Color.Theme.softBrown)
                
                Text("5. Your Rights".localized)
                    .font(.system(.headline, design: .rounded))
                    .fontWeight(.semibold)
                    .foregroundStyle(Color.Theme.primaryBlue)
                    .padding(.top)
                
                Text("You have the right to:\n\n• Access your personal data\n• Delete your account and data\n• Opt out of data collection (though this may limit app functionality)\n• Contact us with privacy concerns".localized)
                    .font(.system(.body, design: .rounded))
                    .foregroundStyle(Color.Theme.softBrown)
                
                Text("6. Contact Us".localized)
                    .font(.system(.headline, design: .rounded))
                    .fontWeight(.semibold)
                    .foregroundStyle(Color.Theme.primaryBlue)
                    .padding(.top)
                
                Text("For privacy-related questions, contact us at:\n\nEmail: support@roadtriproyale.com".localized)
                    .font(.system(.body, design: .rounded))
                    .foregroundStyle(Color.Theme.softBrown)
                }
                .padding()
            }
        }
        .navigationTitle("Privacy Policy".localized)
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Done".localized) {
                    dismiss()
                }
                .font(.system(.body, design: .rounded))
                .fontWeight(.semibold)
                .foregroundStyle(Color.Theme.primaryBlue)
            }
        }
    }
}

// MARK: - Previews

#Preview("Help & About") {
    NavigationStack {
        HelpAboutView()
    }
}

#Preview("Acknowledgements") {
    NavigationStack {
        AcknowledgementsView()
    }
}

#Preview("Terms of Service") {
    NavigationStack {
        TermsView()
    }
}
