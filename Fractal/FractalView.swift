import SwiftUI

// MARK: - API Helper Structs (Normally in their own files)

/// A helper to safely load the API key from the Secrets.plist file.
struct Secrets {
    static var apiKey: String {
        guard let url = Bundle.main.url(forResource: "Secrets", withExtension: "plist"),
              let data = try? Data(contentsOf: url),
              let secrets = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any] else {
            return ""
        }
        return secrets["GroqAPIKey"] as? String ?? ""
    }
}

/// Codable structs to represent the JSON data for the Groq API request.
struct GroqRequest: Codable {
    let messages: [Message]
    let model: String
}

struct Message: Codable {
    let role: String
    let content: String
}

/// Codable structs to decode the JSON data from the Groq API response.
struct GroqResponse: Codable {
    let choices: [Choice]
}

struct Choice: Codable {
    let message: ResponseMessage
}

struct ResponseMessage: Codable {
    let role: String
    let content: String
}

/// Custom Error type for our API calls
enum APIError: Error, LocalizedError {
    case missingAPIKey
    case invalidURL
    case requestFailed(Error)
    case decodingFailed(Error)
    case noContent
    
    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            return "API Key is missing. Please add it to Secrets.plist."
        case .invalidURL:
            return "The API endpoint URL is invalid."
        case .requestFailed:
            return "The network request failed. Please check your connection."
        case .decodingFailed:
            return "Failed to process the response from the server."
        case .noContent:
            return "The AI returned no content. Please try again."
        }
    }
}


// MARK: - Main View

// This view encapsulates the entire user experience for the Fractal app.
struct FractalView: View {

    // MARK: - State Management
    
    private enum AppState {
        case enteringGoal
        case deconstructing
        case showingFirstStep
    }
    
    @State private var currentAppState: AppState = .enteringGoal
    @State private var userGoal: String = ""
    @State private var firstStep: String = ""
    
    // New state for handling API errors
    @State private var apiError: APIError?
    @State private var isShowingErrorAlert = false
    
    private let hapticGenerator = UIImpactFeedbackGenerator(style: .medium)

    // MARK: - Core View
    
    var body: some View {
        ZStack {
            Color(UIColor.systemGroupedBackground).ignoresSafeArea()
            
            switch currentAppState {
            case .enteringGoal:
                goalEntryView
                    .transition(.opacity)
            case .deconstructing:
                deconstructingView
                    .transition(.opacity)
            case .showingFirstStep:
                firstStepView
                    .transition(.opacity)
            }
        }
        // Alert to show the user if an API error occurs
        .alert("Error", isPresented: $isShowingErrorAlert, presenting: apiError) { error in
            Button("OK") {}
        } message: { error in
            Text(error.localizedDescription)
        }
    }
    
    // MARK: - Subviews (No changes here, they adapt to state)

    private var goalEntryView: some View {
        VStack(spacing: 20) {
            Spacer()
            
            Image(systemName: "sparkles")
                .font(.system(size: 50))
                .foregroundColor(.accentColor)
            
            Text("Fractal")
                .font(.system(size: 48, weight: .bold, design: .rounded))
                .foregroundColor(.primary)

            Text("Tell me a huge, intimidating goal. \nI'll give you the first, tiny step.")
                .font(.headline)
                .fontWeight(.medium)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            TextField("e.g., Run a marathon, write a novel...", text: $userGoal)
                .textFieldStyle(.plain)
                .padding()
                .background(Color(UIColor.systemBackground))
                .cornerRadius(12)
                .font(.title3)
                .shadow(color: .black.opacity(0.05), radius: 5, y: 3)
                .padding(.horizontal, 30)
                .padding(.top)

            Button(action: {
                // We now wrap the async call in a Task
                Task {
                    await beginDeconstruction()
                }
            }) {
                Text("Break It Down")
                    .font(.title3)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(Color.accentColor)
                    .cornerRadius(12)
                    .shadow(color: Color.accentColor.opacity(0.4), radius: 8, y: 5)
            }
            .padding(.horizontal, 30)
            .disabled(userGoal.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || currentAppState == .deconstructing)
            
            Spacer()
            Spacer()
        }
        .padding()
    }
    
    private var deconstructingView: some View {
        VStack(spacing: 20) {
            ProgressView()
                .scaleEffect(1.5)
            Text("Deconstructing your ambition...")
                .font(.title2)
                .foregroundColor(.secondary)
        }
    }
    
    private var firstStepView: some View {
        VStack(alignment: .center, spacing: 15) {
            VStack {
                Text("YOUR GOAL")
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundColor(.secondary)
                Text(userGoal)
                    .font(.title2)
                    .fontWeight(.semibold)
                    .multilineTextAlignment(.center)
                    .foregroundColor(.primary)
            }
            .padding(.top, 40)
            
            Divider().padding(.vertical)
            
            VStack {
                Text("YOUR FIRST STEP")
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundColor(.secondary)
                
                Text(firstStep)
                    .font(.system(size: 32, weight: .bold, design: .rounded))
                    .multilineTextAlignment(.center)
                    .foregroundColor(.accentColor)
                    .padding(.vertical)
            }
            
            Spacer()
            
            ShareLink(
                item: "My huge goal: \"\(userGoal)\"\n\nMy laughably easy first step from Fractal: \"\(firstStep)\" #FractalApp"
            ) {
                Label("Share the Absurdity", systemImage: "square.and.arrow.up")
                    .font(.headline)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(Color.accentColor)
                    .cornerRadius(12)
            }
            
            Button("I did it! (or new goal)", action: resetApp)
                .font(.headline)
                .padding()
                .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, 30)
        .padding(.bottom)
    }
    
    // MARK: - Logic & Actions (Major Changes Here)

    /// **MODIFIED:** Now an async function that calls the Groq API.
    private func beginDeconstruction() async {
        hapticGenerator.impactOccurred()
        
        withAnimation {
            currentAppState = .deconstructing
        }
        
        do {
            let generatedStep = try await generateFirstStepFromGroq(for: userGoal)
            
            // Update UI on the main thread
            await MainActor.run {
                self.firstStep = generatedStep
                self.hapticGenerator.impactOccurred()
                withAnimation {
                    self.currentAppState = .showingFirstStep
                }
            }
        } catch let error as APIError {
            // Handle known API errors
            await MainActor.run {
                self.apiError = error
                self.isShowingErrorAlert = true
                withAnimation { self.currentAppState = .enteringGoal }
            }
        } catch {
            // Handle other unexpected errors
            await MainActor.run {
                self.apiError = .requestFailed(error)
                self.isShowingErrorAlert = true
                withAnimation { self.currentAppState = .enteringGoal }
            }
        }
    }
    
    private func resetApp() {
        withAnimation {
            currentAppState = .enteringGoal
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            userGoal = ""
            firstStep = ""
        }
    }
    
    // MARK: - Core AI Function (NEW - Groq API Integration)
    
    /// This function calls the Groq API to generate a first step.
    private func generateFirstStepFromGroq(for goal: String) async throws -> String {
        let apiKey = Secrets.apiKey
        guard !apiKey.isEmpty else {
            throw APIError.missingAPIKey
        }
        
        guard let url = URL(string: "https://api.groq.com/openai/v1/chat/completions") else {
            throw APIError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let systemPrompt = """
        You are an expert in breaking down huge, intimidating goals into laughably simple first steps.
        Your job is to defeat procrastination by lowering 'activation energy'.
        The user will give you a goal. Your response MUST BE ONLY the single, tiny first step.
        It should be encouraging and almost ridiculously easy.
        DO NOT add any extra text, explanations, or pleasantries. Just the single sentence for the step.
        For example, if the goal is "write a book", a good response is "Open a new document and title it.".
        If the goal is "lose 50 pounds", a good response is "Put your gym shoes by the door.".
        """
        
        let requestBody = GroqRequest(
            messages: [
                Message(role: "system", content: systemPrompt),
                Message(role: "user", content: goal)
            ],
            model: "llama3-8b-8192" // The model you specified
        )
        
        request.httpBody = try JSONEncoder().encode(requestBody)
        
        let (data, _) = try await URLSession.shared.data(for: request)
        
        do {
            let response = try JSONDecoder().decode(GroqResponse.self, from: data)
            if let firstChoice = response.choices.first {
                // Clean up the response, as LLMs sometimes add extra quotes or whitespace.
                return firstChoice.message.content.trimmingCharacters(in: .whitespacesAndNewlines.union(.init(charactersIn: "\"")))
            } else {
                throw APIError.noContent
            }
        } catch {
            throw APIError.decodingFailed(error)
        }
    }
}


// MARK: - Preview Provider

struct FractalView_Previews: PreviewProvider {
    static var previews: some View {
        FractalView()
    }
}
