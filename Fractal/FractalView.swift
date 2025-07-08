import SwiftUI

// MARK: - Data Models & API Helpers

struct Goal: Identifiable, Codable {
    let id: UUID
    var title: String
    var steps: [String]
    var startMonth: Int
    var startYear: Int
    var endMonth: Int
    var endYear: Int
    var isLoading: Bool = false
    
    var dateRangeString: String {
        let monthSymbols = DateFormatter().shortMonthSymbols
        guard let startSym = monthSymbols?[safe: startMonth - 1],
              let endSym = monthSymbols?[safe: endMonth - 1] else {
            return ""
        }
        return "\(startSym) \(startYear) - \(endSym) \(endYear)"
    }
}

extension Collection {
    subscript(safe index: Index) -> Element? {
        return indices.contains(index) ? self[index] : nil
    }
}

// RESTORED: Full APIError enum for proper error handling.
enum APIError: Error, LocalizedError {
    case missingAPIKey, invalidURL, requestFailed(Error), decodingFailed(Error), noContent, parsingFailed
    
    var errorDescription: String? {
        switch self {
        case .missingAPIKey: return "API Key is missing. Please add it to Secrets.plist."
        case .invalidURL: return "The API endpoint URL is invalid."
        case .requestFailed: return "The network request failed. Check your connection."
        case .decodingFailed: return "Failed to process the response from the server."
        case .noContent: return "The AI returned no content. Please try again."
        case .parsingFailed: return "Could not parse the steps from the AI's response."
        }
    }
}

// RESTORED: These structs are required for the API call to work.
struct Secrets {
    static var apiKey: String {
        guard let url = Bundle.main.url(forResource: "Secrets", withExtension: "plist"),
              let data = try? Data(contentsOf: url),
              let secrets = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any] else { return "" }
        return secrets["GroqAPIKey"] as? String ?? ""
    }
}
struct GroqRequest: Codable { let messages: [Message]; let model: String }
struct Message: Codable { let role: String; let content: String }
struct GroqResponse: Codable { let choices: [Choice] }
struct Choice: Codable { let message: ResponseMessage }
struct ResponseMessage: Codable { let role: String; let content: String }


// MARK: - Main View Controller

struct FractalView: View {
    @AppStorage("userGoals_v2") private var goalsData: Data?
    @State private var goals: [Goal] = []
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
                    AddGoalSheet { title, sMonth, sYear, eMonth, eYear in
                        Task {
                            await addNewGoal(title: title, startMonth: sMonth, startYear: sYear, endMonth: eMonth, endYear: eYear)
                        }
                    }
                }
                .onAppear(perform: loadGoals)
                .alert("Error", isPresented: $isShowingErrorAlert, presenting: apiError) { error in
                    Button("OK") {}
                } message: { error in
                    Text(error.localizedDescription)
                }
        }
    }
    
    // MARK: - Subviews
    
    @ViewBuilder
    private var goalListView: some View {
        if goals.isEmpty {
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
                    // MODIFIED: Pass the onDelete closure to the detail view.
                    NavigationLink(destination: GoalDetailView(goal: goal, onDelete: {
                        deleteGoal(id: goal.id)
                    })) {
                        HStack {
                            VStack(alignment: .leading, spacing: 5) {
                                Text(goal.title)
                                    .font(.headline)
                                Text(goal.dateRangeString)
                                    .font(.caption.bold())
                                    .foregroundColor(.accentColor)
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
                .onDelete(perform: deleteGoalFromSwipe) // Keep swipe-to-delete
            }
        }
    }
    
    // MARK: - Data & API Logic
    
    private func addNewGoal(title: String, startMonth: Int, startYear: Int, endMonth: Int, endYear: Int) async {
        let newGoal = Goal(id: UUID(), title: title, steps: [], startMonth: startMonth, startYear: startYear, endMonth: endMonth, endYear: endYear, isLoading: true)
                           
        goals.insert(newGoal, at: 0)
        saveGoals()
        
        do {
            let steps = try await generateStepsFromGroq(for: title)
            if let index = goals.firstIndex(where: { $0.id == newGoal.id }) {
                goals[index].steps = steps
                goals[index].isLoading = false
                saveGoals()
            }
        } catch let error as APIError {
            handle(error: error, forGoalID: newGoal.id)
        } catch {
            handle(error: .requestFailed(error), forGoalID: newGoal.id)
        }
    }
    
    // FIXED: This function is now fully implemented.
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
            
            let parsedSteps = content.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }.map { line -> String in
                if let range = line.range(of: "^\\d+\\.\\s*", options: .regularExpression) {
                    return String(line[range.upperBound...])
                }
                return String(line)
            }
            
            guard !parsedSteps.isEmpty else { throw APIError.parsingFailed }
            return parsedSteps
            
        } catch { throw APIError.decodingFailed(error) }
    }
    
    // FIXED: Persistence functions are now implemented.
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
    
    private func deleteGoalFromSwipe(at offsets: IndexSet) {
        goals.remove(atOffsets: offsets)
        saveGoals()
    }
    
    // NEW: Function to delete a specific goal by its ID.
    private func deleteGoal(id: UUID) {
        goals.removeAll { $0.id == id }
        saveGoals()
    }
    
    // FIXED: Error handler now removes the failed goal.
    private func handle(error: APIError, forGoalID id: UUID?) {
        if let goalID = id {
            goals.removeAll { $0.id == goalID }
            saveGoals()
        }
        self.apiError = error
        self.isShowingErrorAlert = true
    }
}

// MARK: - Detail and Sheet Views

// MODIFIED: Added delete functionality.
struct GoalDetailView: View {
    let goal: Goal
    var onDelete: () -> Void // Closure to trigger deletion in the parent view
    
    @Environment(\.dismiss) var dismiss
    @State private var isShowingConfirmDelete = false
    
    var body: some View {
        List {
            Section {
                HStack {
                    Image(systemName: "calendar")
                    Text(goal.dateRangeString)
                }
                .font(.headline)
                .foregroundColor(.secondary)
            }
            
            Section(header: Text("First Steps")) {
                if goal.steps.isEmpty && !goal.isLoading {
                    Text("No steps generated yet.")
                } else {
                    ForEach(goal.steps, id: \.self) { step in
                        HStack(alignment: .top) {
                            Image(systemName: "circle").padding(.top, 4)
                            Text(step)
                        }
                        .padding(.vertical, 5)
                    }
                }
            }
        }
        .navigationTitle(goal.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(role: .destructive) {
                    isShowingConfirmDelete = true
                } label: {
                    Image(systemName: "trash")
                }
            }
        }
        .confirmationDialog("Delete Goal?", isPresented: $isShowingConfirmDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                onDelete()
                dismiss() // Go back to the list view after deleting
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Are you sure you want to delete \"\(goal.title)\"? This action cannot be undone.")
        }
    }
}

struct AddGoalSheet: View {
    @Environment(\.dismiss) var dismiss
    @State private var newGoalTitle: String = ""
    @State private var startMonth: Int
    @State private var startYear: Int
    @State private var endMonth: Int
    @State private var endYear: Int
    
    private let months = DateFormatter().monthSymbols ?? []
    private let currentYear = Calendar.current.component(.year, from: Date())
    private var years: [Int] { Array(currentYear...(currentYear + 20)) }
    
    private var isFormValid: Bool {
        !newGoalTitle.trimmingCharacters(in: .whitespaces).isEmpty &&
        (endYear > startYear || (endYear == startYear && endMonth >= startMonth))
    }
    var onAdd: (String, Int, Int, Int, Int) -> Void
    
    init(onAdd: @escaping (String, Int, Int, Int, Int) -> Void) {
        let now = Date()
        let cal = Calendar.current
        _startMonth = State(initialValue: cal.component(.month, from: now))
        _startYear = State(initialValue: cal.component(.year, from: now))
        _endMonth = State(initialValue: cal.component(.month, from: now))
        _endYear = State(initialValue: cal.component(.year, from: now))
        self.onAdd = onAdd
    }
    
    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("What's your next big goal?")) {
                    TextField("e.g., Launch a podcast", text: $newGoalTitle)
                }
                
                Section(header: Text("Timeline")) {
                    HStack {
                        Text("Start")
                        Spacer()
                        Picker("Start Month", selection: $startMonth) { ForEach(1...12, id: \.self) { Text(months[$0 - 1]).tag($0) } }.labelsHidden()
                        Picker("Start Year", selection: $startYear) { ForEach(years, id: \.self) { Text(String($0)).tag($0) } }.labelsHidden()
                    }
                    HStack {
                        Text("End")
                        Spacer()
                        Picker("End Month", selection: $endMonth) { ForEach(1...12, id: \.self) { Text(months[$0 - 1]).tag($0) } }.labelsHidden()
                        Picker("End Year", selection: $endYear) { ForEach(years, id: \.self) { Text(String($0)).tag($0) } }.labelsHidden()
                    }
                }
                
                Button("Break It Down") {
                    onAdd(newGoalTitle, startMonth, startYear, endMonth, endYear)
                    dismiss()
                }.disabled(!isFormValid)
            }
            .pickerStyle(.menu)
            .navigationTitle("New Goal")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
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
