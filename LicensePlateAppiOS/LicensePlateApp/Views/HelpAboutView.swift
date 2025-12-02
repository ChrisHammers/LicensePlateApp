//
//  HelpAboutView.swift
//  LicensePlateApp
//
//  Created by Christopher Hammers on 11/11/25.
//

import SwiftUI

struct HelpAboutView: View {
    @Environment(\.dismiss) private var dismiss
    
    @State private var showAbout = false
    @State private var showAcknowledgements = false
    @State private var showFAQ = false
    @State private var showTerms = false
    @State private var showPrivacy = false
    
    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
    }
    
    var body: some View {
        NavigationStack {
            ZStack {
                Color.Theme.background
                    .ignoresSafeArea()
                
                List {
                    Section {
                        VStack(spacing: 12) {
                            SettingNavigationRow(
                                title: "About",
                                description: "Learn about RoadTrip Royale and HammersTechLLC",
                                icon: "info.circle.fill"
                            ) {
                                showAbout = true
                            }
                          
                            Divider()
                            
                            SettingNavigationRow(
                                title: "Acknowledgements",
                                description: "Open source libraries and SDKs we use",
                                icon: "doc.text.fill"
                            ) {
                                showAcknowledgements = true
                            }
                          
                            Divider()
                            
                            SettingNavigationRow(
                                title: "FAQ",
                                description: "Frequently asked questions",
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
                                    
                                    VStack(alignment: .leading, spacing: 6) {
                                        Text("Report a Bug")
                                            .font(.system(.body, design: .rounded))
                                            .fontWeight(.semibold)
                                            .foregroundStyle(Color.Theme.primaryBlue)
                                        
                                        Text("Help us improve by reporting issues")
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
                            
                            Divider()
                            
                            Button {
                                sendEmail(to: "hammerstechllc@gmail.com", subject: "RoadTrip Royale Feature Suggestion")
                            } label: {
                                HStack(spacing: 16) {
                                    Image(systemName: "lightbulb")
                                        .font(.system(size: 20))
                                        .foregroundStyle(Color.Theme.primaryBlue)
                                        .frame(width: 24)
                                    
                                    VStack(alignment: .leading, spacing: 6) {
                                        Text("Suggest a Feature")
                                            .font(.system(.body, design: .rounded))
                                            .fontWeight(.semibold)
                                            .foregroundStyle(Color.Theme.primaryBlue)
                                        
                                        Text("Share your ideas for new features")
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
                            
                            Divider()
                            
                            Button {
                                sendEmail(to: "hammerstechllc@gmail.com", subject: "RoadTrip Royale Support Issue")
                            } label: {
                                HStack(spacing: 16) {
                                    Image(systemName: "envelope")
                                        .font(.system(size: 20))
                                        .foregroundStyle(Color.Theme.primaryBlue)
                                        .frame(width: 24)
                                    
                                    VStack(alignment: .leading, spacing: 6) {
                                        Text("Contact Support")
                                            .font(.system(.body, design: .rounded))
                                            .fontWeight(.semibold)
                                            .foregroundStyle(Color.Theme.primaryBlue)
                                        
                                        Text("Get help with the app")
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
                            
                            Divider()
                            
                            // App Version and Legal
                            VStack(spacing: 12) {
                                Text("App Version \(appVersion)")
                                    .font(.system(.caption, design: .rounded))
                                    .foregroundStyle(Color.Theme.softBrown)
                                
                                HStack(spacing: 20) {
                                    // Terms button - isolated tap area
                                    Text("Terms")
                                        .font(.system(.caption, design: .rounded))
                                        .foregroundStyle(Color.Theme.primaryBlue)
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 6)
                                        .contentShape(Rectangle())
                                        .onTapGesture {
                                            showTerms = true
                                        }
                                    
                                    Text("·")
                                        .font(.system(.caption, design: .rounded))
                                        .foregroundStyle(Color.Theme.softBrown)
                                        .allowsHitTesting(false)
                                    
                                    // Privacy button - isolated tap area
                                    Text("Privacy")
                                        .font(.system(.caption, design: .rounded))
                                        .foregroundStyle(Color.Theme.primaryBlue)
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 6)
                                        .contentShape(Rectangle())
                                        .onTapGesture {
                                            showPrivacy = true
                                        }
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
            .navigationTitle("Help & About")
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarBackButtonHidden(true)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        dismiss()
                    }
                    .font(.system(.body, design: .rounded))
                    .fontWeight(.semibold)
                    .foregroundStyle(Color.Theme.primaryBlue)
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
    }
    
    private func sendEmail(to email: String, subject: String) {
        let encodedSubject = subject.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? subject
        if let url = URL(string: "mailto:\(email)?subject=\(encodedSubject)") {
            UIApplication.shared.open(url)
        }
    }
}

// MARK: - Help & About Sub-Views

struct AboutView: View {
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        ZStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text("RoadTrip Royale")
                        .font(.system(.largeTitle, design: .rounded))
                        .fontWeight(.bold)
                        .foregroundStyle(Color.Theme.primaryBlue)
                    
                    Text("About the App")
                        .font(.system(.title2, design: .rounded))
                        .fontWeight(.semibold)
                        .foregroundStyle(Color.Theme.primaryBlue)
                    
                    Text("RoadTrip Royale is a fun and engaging license plate tracking game that lets you collect license plates from across the United States, Canada, and Mexico during your road trips. Spot plates, track your progress, and see your collection grow on an interactive map!")
                        .font(.system(.body, design: .rounded))
                        .foregroundStyle(Color.Theme.softBrown)
                    
                    Text("About HammersTechLLC")
                        .font(.system(.title2, design: .rounded))
                        .fontWeight(.semibold)
                        .foregroundStyle(Color.Theme.primaryBlue)
                        .padding(.top)
                    
                    Text("RoadTrip Royale is developed by HammersTechLLC, a software development company dedicated to creating innovative and user-friendly mobile applications. We're passionate about building apps that make everyday activities more enjoyable and engaging.")
                        .font(.system(.body, design: .rounded))
                        .foregroundStyle(Color.Theme.softBrown)
                    
                    Text("Contact")
                        .font(.system(.title3, design: .rounded))
                        .fontWeight(.semibold)
                        .foregroundStyle(Color.Theme.primaryBlue)
                        .padding(.top)
                    
                    Text("Email: hammerstechllc@gmail.com")
                        .font(.system(.body, design: .rounded))
                        .foregroundStyle(Color.Theme.softBrown)
                }
                .padding()
            }
        }
        .background(Color.Theme.background)
        .navigationTitle("About")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Done") {
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
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Acknowledgements")
                    .font(.system(.largeTitle, design: .rounded))
                    .fontWeight(.bold)
                    .foregroundStyle(Color.Theme.primaryBlue)
                
                Text("RoadTrip Royale uses the following open source libraries and SDKs:")
                    .font(.system(.body, design: .rounded))
                    .foregroundStyle(Color.Theme.softBrown)
                
                VStack(alignment: .leading, spacing: 16) {
                    AcknowledgementItem(
                        name: "Firebase",
                        description: "Backend services including Authentication, Firestore, and Storage",
                        url: "https://firebase.google.com"
                    )
                    
                    AcknowledgementItem(
                        name: "Google Sign-In",
                        description: "OAuth authentication for Google accounts",
                        url: "https://developers.google.com/identity/sign-in/ios"
                    )
                    
                    AcknowledgementItem(
                        name: "Apple Authentication Services",
                        description: "Sign in with Apple integration",
                        url: "https://developer.apple.com/sign-in-with-apple/"
                    )
                    
                    AcknowledgementItem(
                        name: "SwiftUI",
                        description: "Apple's declarative UI framework",
                        url: "https://developer.apple.com/xcode/swiftui/"
                    )
                    
                    AcknowledgementItem(
                        name: "SwiftData",
                        description: "Apple's data persistence framework",
                        url: "https://developer.apple.com/documentation/swiftdata"
                    )
                    
                    AcknowledgementItem(
                        name: "MapKit",
                        description: "Apple's mapping and location services",
                        url: "https://developer.apple.com/mapkit/"
                    )
                    
                    AcknowledgementItem(
                        name: "Speech Framework",
                        description: "Apple's speech recognition framework",
                        url: "https://developer.apple.com/documentation/speech"
                    )
                }
            }
            .padding()
        }
        .background(Color.Theme.background)
        .navigationTitle("Acknowledgements")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Done") {
                    dismiss()
                }
                .font(.system(.body, design: .rounded))
                .fontWeight(.semibold)
                .foregroundStyle(Color.Theme.primaryBlue)
            }
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
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text("Frequently Asked Questions")
                    .font(.system(.largeTitle, design: .rounded))
                    .fontWeight(.bold)
                    .foregroundStyle(Color.Theme.primaryBlue)
                
                FAQItem(
                    question: "How do I play RoadTrip Royale?",
                    answer: "RoadTrip Royale is a license plate tracking game! During your road trips, keep an eye out for license plates from different states, provinces, or regions. When you spot one, use the app to mark it as found. You can use the List tab to manually select plates, or the Voice tab to speak the state/province name. Track your progress and see your collection grow on the interactive map!"
                )
                
                FAQItem(
                    question: "How do I create a trip?",
                    answer: "On the main screen, tap the 'Create Trip' button. You can give your trip a custom name, or leave it blank to use the date and time automatically. Once created, tap on the trip to start tracking license plates!"
                )
                
                FAQItem(
                    question: "How does the Voice feature work?",
                    answer: "Tap the Voice tab, then press the microphone button. Speak the name of the state or province you see (e.g., 'California' or 'Ontario'). The app will listen and try to match what you said to a valid license plate region. If a match is found, you'll be asked to confirm before adding it to your collection."
                )
                
                FAQItem(
                    question: "Can I track plates from multiple countries?",
                    answer: "Yes! RoadTrip Royale supports license plates from the United States, Canada, and Mexico. The map will automatically switch to show the correct country as you scroll through the list of regions."
                )
                
                FAQItem(
                    question: "How do I see my progress?",
                    answer: "On the trip screen, you'll see summary chips showing how many plates you've found and how many remain. The map at the top shows all found regions highlighted in yellow. You can tap the map to view it full-screen for a better look!"
                )
                
                FAQItem(
                    question: "Can I share my trips with others?",
                    answer: "Currently, trips are stored locally on your device. Future updates may include sharing and collaboration features. Stay tuned!"
                )
                
                FAQItem(
                    question: "Do I need an internet connection?",
                    answer: "RoadTrip Royale works offline! You can create trips and track license plates without an internet connection. If you sign in with an account, your data will sync to the cloud when you're online."
                )
            }
            .padding()
        }
        .background(Color.Theme.background)
        .navigationTitle("FAQ")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Done") {
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
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(question)
                .font(.system(.headline, design: .rounded))
                .fontWeight(.semibold)
                .foregroundStyle(Color.Theme.primaryBlue)
            
            Text(answer)
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

struct TermsView: View {
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Terms of Service")
                    .font(.system(.largeTitle, design: .rounded))
                    .fontWeight(.bold)
                    .foregroundStyle(Color.Theme.primaryBlue)
                
                Text("Last Updated: \(Date().formatted(date: .abbreviated, time: .omitted))")
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(Color.Theme.softBrown)
                
                Text("1. Acceptance of Terms")
                    .font(.system(.headline, design: .rounded))
                    .fontWeight(.semibold)
                    .foregroundStyle(Color.Theme.primaryBlue)
                    .padding(.top)
                
                Text("By downloading, installing, or using RoadTrip Royale, you agree to be bound by these Terms of Service. If you do not agree to these terms, please do not use the app.")
                    .font(.system(.body, design: .rounded))
                    .foregroundStyle(Color.Theme.softBrown)
                
                Text("2. Use of the App")
                    .font(.system(.headline, design: .rounded))
                    .fontWeight(.semibold)
                    .foregroundStyle(Color.Theme.primaryBlue)
                    .padding(.top)
                
                Text("RoadTrip Royale is provided for personal, non-commercial use. You may not use the app for any illegal or unauthorized purpose. You are responsible for maintaining the security of your account.")
                    .font(.system(.body, design: .rounded))
                    .foregroundStyle(Color.Theme.softBrown)
                
                Text("3. User Content")
                    .font(.system(.headline, design: .rounded))
                    .fontWeight(.semibold)
                    .foregroundStyle(Color.Theme.primaryBlue)
                    .padding(.top)
                
                Text("You retain ownership of any data you create using RoadTrip Royale. By using the app, you grant HammersTechLLC the right to store and process your data to provide the service.")
                    .font(.system(.body, design: .rounded))
                    .foregroundStyle(Color.Theme.softBrown)
                
                Text("4. Limitation of Liability")
                    .font(.system(.headline, design: .rounded))
                    .fontWeight(.semibold)
                    .foregroundStyle(Color.Theme.primaryBlue)
                    .padding(.top)
                
                Text("HammersTechLLC shall not be liable for any indirect, incidental, special, or consequential damages arising from your use of RoadTrip Royale.")
                    .font(.system(.body, design: .rounded))
                    .foregroundStyle(Color.Theme.softBrown)
                
                Text("5. Changes to Terms")
                    .font(.system(.headline, design: .rounded))
                    .fontWeight(.semibold)
                    .foregroundStyle(Color.Theme.primaryBlue)
                    .padding(.top)
                
                Text("We reserve the right to modify these terms at any time. Continued use of the app after changes constitutes acceptance of the new terms.")
                    .font(.system(.body, design: .rounded))
                    .foregroundStyle(Color.Theme.softBrown)
            }
            .padding()
        }
        .background(Color.Theme.background)
        .navigationTitle("Terms of Service")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Done") {
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
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Privacy Policy")
                    .font(.system(.largeTitle, design: .rounded))
                    .fontWeight(.bold)
                    .foregroundStyle(Color.Theme.primaryBlue)
                
                Text("Last Updated: \(Date().formatted(date: .abbreviated, time: .omitted))")
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(Color.Theme.softBrown)
                
                Text("1. Information We Collect")
                    .font(.system(.headline, design: .rounded))
                    .fontWeight(.semibold)
                    .foregroundStyle(Color.Theme.primaryBlue)
                    .padding(.top)
                
                Text("RoadTrip Royale collects the following information:\n\n• Account information (username, email, phone) if you create an account\n• Trip data and license plate tracking information\n• Location data (optional, with your permission)\n• Device information for app functionality")
                    .font(.system(.body, design: .rounded))
                    .foregroundStyle(Color.Theme.softBrown)
                
                Text("2. How We Use Your Information")
                    .font(.system(.headline, design: .rounded))
                    .fontWeight(.semibold)
                    .foregroundStyle(Color.Theme.primaryBlue)
                    .padding(.top)
                
                Text("We use your information to:\n\n• Provide and improve the app's functionality\n• Sync your data across devices (if you sign in)\n• Respond to support requests\n• Ensure app security and prevent fraud")
                    .font(.system(.body, design: .rounded))
                    .foregroundStyle(Color.Theme.softBrown)
                
                Text("3. Data Storage")
                    .font(.system(.headline, design: .rounded))
                    .fontWeight(.semibold)
                    .foregroundStyle(Color.Theme.primaryBlue)
                    .padding(.top)
                
                Text("Your data is stored locally on your device. If you sign in with an account, your data is also stored securely in Firebase (Google Cloud Platform) to enable syncing across devices.")
                    .font(.system(.body, design: .rounded))
                    .foregroundStyle(Color.Theme.softBrown)
                
                Text("4. Third-Party Services")
                    .font(.system(.headline, design: .rounded))
                    .fontWeight(.semibold)
                    .foregroundStyle(Color.Theme.primaryBlue)
                    .padding(.top)
                
                Text("RoadTrip Royale uses Firebase (Google) for authentication and data storage. Your use of these services is subject to their respective privacy policies.")
                    .font(.system(.body, design: .rounded))
                    .foregroundStyle(Color.Theme.softBrown)
                
                Text("5. Your Rights")
                    .font(.system(.headline, design: .rounded))
                    .fontWeight(.semibold)
                    .foregroundStyle(Color.Theme.primaryBlue)
                    .padding(.top)
                
                Text("You have the right to:\n\n• Access your personal data\n• Delete your account and data\n• Opt out of data collection (though this may limit app functionality)\n• Contact us with privacy concerns")
                    .font(.system(.body, design: .rounded))
                    .foregroundStyle(Color.Theme.softBrown)
                
                Text("6. Contact Us")
                    .font(.system(.headline, design: .rounded))
                    .fontWeight(.semibold)
                    .foregroundStyle(Color.Theme.primaryBlue)
                    .padding(.top)
                
                Text("For privacy-related questions, contact us at:\n\nEmail: hammerstechllc@gmail.com")
                    .font(.system(.body, design: .rounded))
                    .foregroundStyle(Color.Theme.softBrown)
            }
            .padding()
        }
        .background(Color.Theme.background)
        .navigationTitle("Privacy Policy")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Done") {
                    dismiss()
                }
                .font(.system(.body, design: .rounded))
                .fontWeight(.semibold)
                .foregroundStyle(Color.Theme.primaryBlue)
            }
        }
    }
}

