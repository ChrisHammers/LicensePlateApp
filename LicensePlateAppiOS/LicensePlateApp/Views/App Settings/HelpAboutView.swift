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
                                sendEmail(to: "hammerstechllc@gmail.com", subject: "RoadTrip Royale Bug Report")
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
                                sendEmail(to: "hammerstechllc@gmail.com", subject: "RoadTrip Royale Feature Suggestion")
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
                                sendEmail(to: "hammerstechllc@gmail.com", subject: "RoadTrip Royale Support Issue")
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
                    
                    Text("Email: hammerstechllc@gmail.com".localized)
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
    
    var body: some View {
        AppBackgroundView {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                Text("Terms of Service".localized)
                    .font(.system(.largeTitle, design: .rounded))
                    .fontWeight(.bold)
                    .foregroundStyle(Color.Theme.primaryBlue)
                
                Text("Last Updated: %@".localized(Date().formatted(date: .abbreviated, time: .omitted)))
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(Color.Theme.softBrown)
                
                Text("1. Acceptance of Terms".localized)
                    .font(.system(.headline, design: .rounded))
                    .fontWeight(.semibold)
                    .foregroundStyle(Color.Theme.primaryBlue)
                    .padding(.top)
                
                Text("By downloading, installing, or using RoadTrip Royale, you agree to be bound by these Terms of Service. If you do not agree to these terms, please do not use the app.".localized)
                    .font(.system(.body, design: .rounded))
                    .foregroundStyle(Color.Theme.softBrown)
                
                Text("2. Use of the App".localized)
                    .font(.system(.headline, design: .rounded))
                    .fontWeight(.semibold)
                    .foregroundStyle(Color.Theme.primaryBlue)
                    .padding(.top)
                
                Text("RoadTrip Royale is provided for personal, non-commercial use. You may not use the app for any illegal or unauthorized purpose. You are responsible for maintaining the security of your account.".localized)
                    .font(.system(.body, design: .rounded))
                    .foregroundStyle(Color.Theme.softBrown)
                
                Text("3. User Content".localized)
                    .font(.system(.headline, design: .rounded))
                    .fontWeight(.semibold)
                    .foregroundStyle(Color.Theme.primaryBlue)
                    .padding(.top)
                
                Text("You retain ownership of any data you create using RoadTrip Royale. By using the app, you grant HammersTechLLC the right to store and process your data to provide the service.".localized)
                    .font(.system(.body, design: .rounded))
                    .foregroundStyle(Color.Theme.softBrown)
                
                Text("4. Limitation of Liability".localized)
                    .font(.system(.headline, design: .rounded))
                    .fontWeight(.semibold)
                    .foregroundStyle(Color.Theme.primaryBlue)
                    .padding(.top)
                
                Text("HammersTechLLC shall not be liable for any indirect, incidental, special, or consequential damages arising from your use of RoadTrip Royale.".localized)
                    .font(.system(.body, design: .rounded))
                    .foregroundStyle(Color.Theme.softBrown)
                
                Text("5. Changes to Terms".localized)
                    .font(.system(.headline, design: .rounded))
                    .fontWeight(.semibold)
                    .foregroundStyle(Color.Theme.primaryBlue)
                    .padding(.top)
                
                Text("We reserve the right to modify these terms at any time. Continued use of the app after changes constitutes acceptance of the new terms.".localized)
                    .font(.system(.body, design: .rounded))
                    .foregroundStyle(Color.Theme.softBrown)
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
                
                Text("For privacy-related questions, contact us at:\n\nEmail: hammerstechllc@gmail.com".localized)
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
