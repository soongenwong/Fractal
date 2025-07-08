import SwiftUI

// MARK: - Data Models & API Helpers

/// MODIFIED: Goal struct now includes start and end dates.
struct Goal: Identifiable, Codable {
    let id: UUID
    var title: String
    var steps: [String]
    
    // New properties for date range
    var startMonth: Int
    var startYear: Int
    var endMonth: Int
    var endYear: Int
    
    var isLoading: Bool = false
    
    /// A helper to format the date range for display.
    var dateRangeString: String {
        let monthSymbols = DateFormatter().shortMonthSymbols
        guard let startSym = monthSymbols?[safe: startMonth - 1],
              let endSym = monthSymbols?[safe: endMonth - 1] else {
            return ""
        }
        return "\(startSym) \(startYear) - \(endSym) \(endYear)"
    }
}

// Helper to prevent array index out of bounds crashes
extension Collection {
    subscript(safe index: Index) -> Element? {
        return indices.contains(index) ? self[index] : nil
    }
}

// (APIError, Secrets, and Groq Codable structs remain the same)
enum APIError: Error, LocalizedError {
    case unknown
    /* ... same as before ... */
}
struct Secrets { /* ... same as before ... */ }
struct GroqRequest: Codable { /* ... same as before ... */ }
struct Message: Codable { /* ... same as before ... */ }
struct GroqResponse: Codable { /* ... same as before ... */ }
struct Choice: Codable { /* ... same as before ... */ }
struct ResponseMessage: Codable { /* ... same as before ... */ }


// MARK: - Main View Controller

struct FractalView: View {
    @AppStorage("userGoals_v2") private var goalsData: Data? // Changed key to avoid conflicts with old data structure
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
                    // MODIFIED: The sheet now passes back all the necessary data.
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
                    NavigationLink(destination: GoalDetailView(goal: goal)) {
                        HStack {
                            VStack(alignment: .leading, spacing: 5) {
                                Text(goal.title)
                                    .font(.headline)
                                
                                // MODIFIED: Added the date range display
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
                .onDelete(perform: deleteGoal)
            }
        }
    }
    
    // MARK: - Data & API Logic
    
    /// MODIFIED: Function now accepts date parameters to create the Goal object.
    private func addNewGoal(title: String, startMonth: Int, startYear: Int, endMonth: Int, endYear: Int) async {
        let newGoal = Goal(id: UUID(),
                           title: title,
                           steps: [],
                           startMonth: startMonth,
                           startYear: startYear,
                           endMonth: endMonth,
                           endYear: endYear,
                           isLoading: true)
                           
        goals.insert(newGoal, at: 0)
        saveGoals()
        
        // The rest of the function (API call, error handling) remains the same
        do {
            let steps = try await generateStepsFromGroq(for: title)
            if let index = goals.firstIndex(where: { $0.id == newGoal.id }) {
                goals[index].steps = steps
                goals[index].isLoading = false
                saveGoals()
            }
        } catch let error as APIError {
            handle(error: error)
            goals.removeAll { $0.id == newGoal.id }
            saveGoals()
        } catch {
            handle(error: .unknown)
            goals.removeAll { $0.id == newGoal.id }
            saveGoals()
        }
    }
    
    private func generateStepsFromGroq(for goal: String) async throws -> [String] {
        // TODO: Replace with actual API call logic
        return []
    }
    private func loadGoals() { /* ... */ }
    private func saveGoals() { /* ... */ }
    private func deleteGoal(at offsets: IndexSet) { /* ... */ }
    private func handle(error: APIError) { /* ... */ }
}


// MARK: - Detail and Sheet Views

struct GoalDetailView: View {
    let goal: Goal
    
    var body: some View {
        List {
            // MODIFIED: Show the date range at the top of the detail view.
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
    }
}


/// MODIFIED: A completely overhauled sheet with date pickers.
struct AddGoalSheet: View {
    @Environment(\.dismiss) var dismiss
    @State private var newGoalTitle: String = ""
    
    // State for date pickers
    @State private var startMonth: Int
    @State private var startYear: Int
    @State private var endMonth: Int
    @State private var endYear: Int
    
    // Data for pickers
    private let months = DateFormatter().monthSymbols ?? []
    private let currentYear = Calendar.current.component(.year, from: Date())
    private var years: [Int] { Array(currentYear...(currentYear + 20)) }
    
    // Validation
    private var isFormValid: Bool {
        if newGoalTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return false
        }
        // Check if end date is after start date
        if endYear < startYear {
            return false
        }
        if endYear == startYear && endMonth < startMonth {
            return false
        }
        return true
    }
    
    // The updated closure to pass all data back
    var onAdd: (String, Int, Int, Int, Int) -> Void
    
    init(onAdd: @escaping (String, Int, Int, Int, Int) -> Void) {
        self.onAdd = onAdd
        
        let calendar = Calendar.current
        let currentDate = Date()
        _startMonth = State(initialValue: calendar.component(.month, from: currentDate))
        _startYear = State(initialValue: calendar.component(.year, from: currentDate))
        
        // Default end date to 3 months from now
        let futureDate = calendar.date(byAdding: .month, value: 3, to: currentDate) ?? currentDate
        _endMonth = State(initialValue: calendar.component(.month, from: futureDate))
        _endYear = State(initialValue: calendar.component(.year, from: futureDate))
    }
    
    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("What's your next big goal?")) {
                    TextField("e.g., Launch a podcast", text: $newGoalTitle)
                }
                
                Section(header: Text("Timeline")) {
                    // Start Date Pickers
                    HStack {
                        Text("Start")
                        Spacer()
                        Picker("", selection: $startMonth) {
                            ForEach(1...12, id: \.self) { month in
                                Text(months[month - 1]).tag(month)
                            }
                        }
                        Picker("", selection: $startYear) {
                            ForEach(years, id: \.self) { year in
                                Text(String(year)).tag(year)
                            }
                        }
                    }
                    
                    // End Date Pickers
                    HStack {
                        Text("End")
                        Spacer()
                        Picker("", selection: $endMonth) {
                            ForEach(1...12, id: \.self) { month in
                                Text(months[month - 1]).tag(month)
                            }
                        }
                        Picker("", selection: $endYear) {
                            ForEach(years, id: \.self) { year in
                                Text(String(year)).tag(year)
                            }
                        }
                    }
                }
                
                Button("Break It Down") {
                    onAdd(newGoalTitle, startMonth, startYear, endMonth, endYear)
                    dismiss()
                }
                .disabled(!isFormValid)
            }
            .pickerStyle(.menu) // A compact style for the pickers
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
