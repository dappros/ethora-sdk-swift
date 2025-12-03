//
//  ContentView.swift
//  ChatAppExample
//
//  Main content view with login/logout
//

import SwiftUI
import Combine
import XMPPChatCore
import XMPPChatUI

struct ContentView: View {
    @StateObject private var appState = AppState()
    @State private var username: String = "yukiraze9@gmail.com"
    @State private var password: String = "Qwerty123"
    @State private var isLoading: Bool = false
    @State private var errorMessage: String?
    
    var body: some View {
        Group {
            if appState.isAuthenticated, let client = appState.xmppClient {
                MainChatView(client: client, appState: appState)
            } else {
                LoginView(
                    username: $username,
                    password: $password,
                    isLoading: $isLoading,
                    errorMessage: $errorMessage,
                    onLogin: {
                        await performLogin()
                    }
                )
            }
        }
        .onAppear {
            // Just check cache status, but DON'T auto-login
            Task { @MainActor in
                if UserStore.shared.isAuthenticated,
                   let user = UserStore.shared.currentUser {
                    print("ℹ️ Found cached user: \(user.email ?? "unknown")")
                    print("   Token exists: \(UserStore.shared.token != nil)")
                    print("   But NOT auto-connecting. User must click Login button.")
                } else {
                    print("ℹ️ No cached user found. User needs to login manually.")
                }
            }
        }
    }
    
    private func performLogin() async {
        isLoading = true
        errorMessage = nil
        
        print("")
        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        print("🔐 USER CLICKED LOGIN BUTTON")
        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        print("📧 Email: \(username)")
        print("")
        
        do {
            print("🌐 Calling AuthAPI.loginWithEmail...")
            
            let loginResponse = try await AuthAPI.loginWithEmail(
                email: username,
                password: password
            )
            
            print("")
            print("✅ Login API call successful!")
            print("💾 Saving user data to UserStore (cache)...")
            
            // Save to UserStore (this will cache it)
            await UserStore.shared.setUser(from: loginResponse)
            
            // Verify it was saved
            let savedToken = await MainActor.run { UserStore.shared.token }
            let savedUser = await MainActor.run { UserStore.shared.currentUser }
            print("✅ UserStore updated:")
            print("   Token saved: \(savedToken != nil ? "YES" : "NO")")
            print("   User saved: \(savedUser?.email ?? "NO")")
            print("   isAuthenticated: \(await MainActor.run { UserStore.shared.isAuthenticated })")
            
            print("")
            print("🔌 Initializing XMPP connection...")
            
            // Initialize XMPP with logged in user
            await appState.initializeXMPPWithLoggedInUser()
            
            print("")
            print("✅ Login complete! User authenticated and XMPP connected.")
            print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
            
        } catch {
            let errorMsg = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            errorMessage = errorMsg
            print("")
            print("❌ Login failed: \(errorMsg)")
            print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        }
        
        isLoading = false
    }
}

struct LoginView: View {
    @Binding var username: String
    @Binding var password: String
    @Binding var isLoading: Bool
    @Binding var errorMessage: String?
    let onLogin: () async -> Void
    
    var body: some View {
        VStack(spacing: 20) {
            Text("XMPP Chat")
                .font(.largeTitle)
                .bold()
            
            if let error = errorMessage {
                Text(error)
                    .foregroundColor(.red)
                    .font(.caption)
                    .padding()
                    .background(Color.red.opacity(0.1))
                    .cornerRadius(8)
            }
            
            TextField("Email", text: $username)
                .textFieldStyle(.roundedBorder)
                .autocapitalization(.none)
                .keyboardType(.emailAddress)
                #if os(iOS)
                .textInputAutocapitalization(.never)
                #endif
            
            SecureField("Password", text: $password)
                .textFieldStyle(.roundedBorder)
            
            Button(action: {
                Task {
                    await onLogin()
                }
            }) {
                if isLoading {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle())
                } else {
                    Text("Login")
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(username.isEmpty || password.isEmpty || isLoading)
        }
        .padding()
    }
}

struct MainChatView: View {
    let client: XMPPClient
    @ObservedObject var appState: AppState
    @StateObject private var roomListViewModel: RoomListViewModel
    @State private var currentUserId: String = ""
    
    init(client: XMPPClient, appState: AppState) {
        self.client = client
        self.appState = appState
        
        // Get currentUserId from UserStore
        let userId = UserStore.shared.currentUser?.id ?? ""
        
        // Initialize view model
        self._roomListViewModel = StateObject(wrappedValue: RoomListViewModel(
            client: client,
            currentUserId: userId
        ))
    }
    
    var body: some View {
        NavigationView {
            RoomListView(viewModel: roomListViewModel)
                .toolbar {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button("Logout") {
                            Task {
                                await appState.logout()
                            }
                        }
                    }
                }
        }
        .onAppear {
            print("")
            print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
            print("📱 MainChatView.onAppear - CALLED!")
            print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
            
            Task { @MainActor in
                // Update currentUserId if needed
                if let user = UserStore.shared.currentUser {
                    currentUserId = user.id
                    print("✅ Current User ID: \(currentUserId)")
                }
                
                // Verify authentication state
                let isAuth = UserStore.shared.isAuthenticated
                let hasToken = UserStore.shared.token != nil
                let tokenPreview = UserStore.shared.token?.prefix(30) ?? "nil"
                print("🔍 Authentication state:")
                print("   isAuthenticated: \(isAuth)")
                print("   hasToken: \(hasToken)")
                print("   token: \(tokenPreview)...")
                
                // Load rooms immediately if authenticated
                if isAuth && hasToken {
                    print("✅ User authenticated, calling loadRooms() NOW...")
                    roomListViewModel.loadRooms()
                } else {
                    print("❌ User not authenticated, cannot load rooms")
                    print("   This means login didn't work or UserStore wasn't updated")
                }
                print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
            }
        }
    }
}

