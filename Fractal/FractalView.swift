import SwiftUI

// MARK: - Data Models & API Helpers (Kept in this file as requested)

/// Represents a single, trackable goal with its deconstructed steps.
struct Goal: Identifiable, Codable {
    let id: UUID
    var title: String
    var steps: [String]
    var isLoading: Bool = false
}

// Custom Error type for our API calls
enum APIError: Error, LocalizedError {
    case missingAPIKey, invalidURL, requestFailed(Error), decodingFailed(Error), noContent, parsingFailed
    
    var errorDescription: String? {
        switch self {
        case .missingAPIKey: "API Key is missing. Please add it to Secrets.plist."
        case .invalidURL: "The API endpoint URL is invalid."
        case .requestFailed: "The network request failed. Please check your connection."
        case .decodingFailed: "Failed to process the response from the server."
        case .noContent: "The AI returned no content. Please try again."
        case .parsingFailed: "Could not parse the steps from the AI's response."
        }
    }
}

// API Key Loader
struct Secrets {
    static var apiKey: String {
        guard let url = Bundle.main.url(forResource: "Secrets", withExtension: "plist"),
              let data = try? Data(contentsOf: url),
              let secrets = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any] else { return "" }
        return secrets["GroqAPIKey"] as? String ?? ""
    }
}

// Groq API Codable Structs
struct GroqRequest: Codable { let messages: [Message]; let model: String }
struct Message: Codable { let role: String; let content: String }
struct GroqResponse: Codable { let choices: [Choice] }
struct Choice: Codable { let message: ResponseMessage }
struct ResponseMessage: Codable { let role: String; let content: String }


// MARK: - Main View Controller

struct FractalView: View {
    // AppStorage is used to persist the goals array on the device.
    @AppStorage("userGoals") private var goalsData: Data?
    
    // The main state for our goals list. Loaded from AppStorage.
    @State private var goals: [Goal] = []
    
    // State to control the presentation of the "Add Goal" sheet and alerts.
    @State private var isShowingAddSheet = false
    @State private var apiError: APIError?
    @State private var isShowingErrorAlert = false
    
    var body: some View {
        NavigationStack {
            goalListView
                .navigationTitle("My Goals")
                .toolbar {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button(action: { isShowingAddSheet = true }) {
                            Image(systemName: "plus.circle.fill")
                                .font(.title2)
                        }
                    }
                }
                .sheet(isPresented: $isShowingAddSheet) {
                    AddGoalSheet { newGoalTitle in
                        // This closure is called when the user taps "Add Goal"
                        Task {
                            await addNewGoal(title: newGoalTitle)
                        }
                    }
                }
                .onAppear(perform: loadGoals) // Load goals when the view appears
                .alert("Error", isPresented: $isShowingErrorAlert, presenting: apiError) { error in
                    Button("OK") {}
                } message: { error in
                    Text(error.localizedDescription)
                }
        }
    }
    
    // MARK: - Subviews
    
    /// The main view displaying the list of user goals.
    @ViewBuilder
    private var goalListView: some View {
        if goals.isEmpty {
            // A nice placeholder for when there are no goals yet.
            VStack {
                Spacer()
                Image(systemName: "moon.stars")
                    .font(.system(size: 60))
                    .foregroundColor(.secondary)
                    .padding(.bottom, 10)
                Text("No Goals Yet")
                    .font(.title2).bold()
                Text("Tap the '+' to add a huge new goal and break it down into tiny steps.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
                Spacer()
                Spacer()
            }
        } else {
            List {
                ForEach(goals) { goal in
                    NavigationLink(destination: GoalDetailView(goal: goal)) {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(goal.title)
                                    .font(.headline)
                                Text(goal.isLoading ? "Breaking it down..." : "\(goal.steps.count) steps")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            if goal.isLoading {
                                ProgressView().padding(.trailing)
                            }
                        }
                        .padding(.vertical, 8)
                    }
                }
                .onDelete(perform: deleteGoal)
            }
        }
    }
    
    // MARK: - Data & API Logic
    
    /// Adds a new goal, shows a loading state, and fetches steps from the API.
    private func addNewGoal(title: String) async {
        let newGoal = Goal(id: UUID(), title: title, steps: [], isLoading: true)
        
        // Add to the list immediately for instant UI feedback
        goals.insert(newGoal, at: 0)
        saveGoals()
        
        do {
            let steps = try await generateStepsFromGroq(for: title)
            
            // Find the goal and update it with the new steps
            if let index = goals.firstIndex(where: { $0.id == newGoal.id }) {
                goals[index].steps = steps
                goals[index].isLoading = false
                saveGoals()
            }
        } catch let error as APIError {
            handle(error: error)
            // If the API fails, remove the temporary goal we added.
            goals.removeAll { $0.id == newGoal.id }
            saveGoals()
        } catch {
            handle(error: .requestFailed(error))
            goals.removeAll { $0.id == newGoal.id }
            saveGoals()
        }
    }
    
    /// Calls the Groq API and parses the response into a list of steps.
    private func generateStepsFromGroq(for goal: String) async throws -> [String] {
        let apiKey = Secrets.apiKey
        guard !apiKey.isEmpty else { throw APIError.missingAPIKey }
        guard let url = URL(string: "https://api.groq.com/openai/v1/chat/completions") else { throw APIError.invalidURL }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let systemPrompt = """
        You are an expert in breaking down huge, intimidating goals into laughably simple first steps.
        The user will give you a goal. Your response MUST BE a numbered list of the first 3-5 tiny, sequential steps.
        Each step must be on a new line. Do not add any extra text, explanations, or pleasantries.
        Example response for goal "Learn to bake bread":
        1. Watch a 5-minute video on "no-knead bread".
        2. Buy a bag of flour.
        3. Find a large bowl in your kitchen.
        """
        
        let requestBody = GroqRequest(messages: [Message(role: "system", content: systemPrompt), Message(role: "user", content: goal)], model: "llama3-8b-8192")
        request.httpBody = try JSONEncoder().encode(requestBody)
        
        let (data, _) = try await URLSession.shared.data(for: request)
        
        do {
            let response = try JSONDecoder().decode(GroqResponse.self, from: data)
            guard let content = response.choices.first?.message.content else { throw APIError.noContent }
            
            // Parse the numbered list into a clean array of strings
            let parsedSteps = content.split(separator: "\n")
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
                .map { line -> String in
                    // Remove "1. ", "2. ", etc. from the beginning of the line
                    if let range = line.range(of: "^\\d+\\.\\s*", options: .regularExpression) {
                        return String(line[range.upperBound...])
                    }
                    return String(line)
                }
            
            guard !parsedSteps.isEmpty else { throw APIError.parsingFailed }
            return parsedSteps
            
        } catch { throw APIError.decodingFailed(error) }
    }
    
    // MARK: - Persistence & Helper Functions
    
    private func loadGoals() {
        guard let data = goalsData else { return }
        if let decodedGoals = try? JSONDecoder().decode([Goal].self, from: data) {
            self.goals = decodedGoals
        }
    }
    
    private func saveGoals() {
        if let encodedData = try? JSONEncoder().encode(goals) {
            self.goalsData = encodedData
        }
    }
    
    private func deleteGoal(at offsets: IndexSet) {
        goals.remove(atOffsets: offsets)
        saveGoals()
    }
    
    private func handle(error: APIError) {
        self.apiError = error
        self.isShowingErrorAlert = true
    }
}


// MARK: - Detail and Sheet Views (Kept in this file as requested)

/// A view that displays the steps for a single goal.
struct GoalDetailView: View {
    let goal: Goal
    
    var body: some View {
        List {
            Section(header: Text("First Steps")) {
                if goal.steps.isEmpty && !goal.isLoading {
                    Text("No steps generated yet. Try adding the goal again.")
                        .foregroundColor(.secondary)
                } else {
                    ForEach(goal.steps, id: \.self) { step in
                        HStack(alignment: .top) {
                            Image(systemName: "circle") // Could be a checkbox later
                                .foregroundColor(.accentColor)
                                .padding(.top, 4)
                            Text(step)
                        }
                        .padding(.vertical, 5)
                    }
                }
            }
        }
        .navigationTitle(goal.title)
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// A sheet view for adding a new goal.
struct AddGoalSheet: View {
    @Environment(\.dismiss) var dismiss
    @State private var newGoalTitle: String = ""
    
    // A closure to pass the new goal title back to the parent view.
    var onAdd: (String) -> Void
    
    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("What's your next big goal?")) {
                    TextField("e.g., Launch a podcast, learn to cook...", text: $newGoalTitle)
                }
                
                Button("Break It Down") {
                    if !newGoalTitle.trimmingCharacters(in: .whitespaces).isEmpty {
                        onAdd(newGoalTitle)
                        dismiss()
                    }
                }
                .disabled(newGoalTitle.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .navigationTitle("New Goal")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}


// MARK: - Preview Provider

struct FractalView_Previews: PreviewProvider {
    static var previews: some View {
        FractalView()
    }
}
