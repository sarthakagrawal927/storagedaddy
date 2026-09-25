import SwiftUI
import DiskCore

/// Keeps long lists browsable without expanding every matching item.
struct ListPagination: View {
    @Binding var page: Int
    let total: Int
    let pageSize: Int
    let noun: String

    private var lastPage: Int { max(0, (total - 1) / pageSize) }

    var body: some View {
        HStack(spacing: 12) {
            Text("\(min(total, page * pageSize + 1))–\(min(total, (page + 1) * pageSize)) of \(total.formatted()) \(noun)")
                .font(.caption).monospacedDigit().foregroundStyle(Tints.secondaryText)
            Spacer(minLength: 8)
            if total > pageSize {
                Button("Previous", systemImage: "chevron.left") { page = max(0, page - 1) }
                    .disabled(page == 0).accessibilityLabel("Previous page of \(noun)")
                Button("Next", systemImage: "chevron.right") { page = min(lastPage, page + 1) }
                    .disabled(page >= lastPage).accessibilityLabel("Next page of \(noun)")
            }
        }.padding(.vertical, 8)
    }
}
