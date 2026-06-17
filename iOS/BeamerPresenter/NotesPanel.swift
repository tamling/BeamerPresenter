import SwiftUI

/// The presenter-only speaker-notes pane shown beside the slide. It shows either
/// parsed `.tex` notes for the current slide, or — for a "notes on second screen"
/// split PDF — the right-hand notes half of the page.
struct NotesPanel: View {
    @EnvironmentObject var model: PresentationModel
    let loadTex: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider().overlay(Color.white.opacity(0.15))
            content
        }
        .background(Color(white: 0.08))
        .foregroundStyle(.white)
    }

    private var header: some View {
        HStack {
            Label("Notes", systemImage: "note.text").font(.headline)
            Spacer()
            Text("\(model.index + 1) / \(model.pageCount)")
                .font(.subheadline.monospacedDigit()).foregroundStyle(.secondary)
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
    }

    @ViewBuilder
    private var content: some View {
        if model.splitNotes {
            PDFPageView(document: model.document, pageIndex: model.index,
                        displayBox: .trimBox)
                .padding(8)
        } else if let note = model.note(for: model.index), !note.isEmpty {
            ScrollView {
                Text(note)
                    .font(.title3)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
                    .padding(14)
            }
        } else {
            emptyState
        }
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Spacer()
            Image(systemName: "note.text").font(.system(size: 34)).foregroundStyle(.secondary)
            Text(model.notesByPage.isEmpty
                 ? "No notes on this slide."
                 : "No note for this slide.")
                .foregroundStyle(.secondary)
            if model.notesByPage.isEmpty {
                Button { loadTex() } label: {
                    Label("Load notes (.tex)…", systemImage: "doc.text")
                }
                .buttonStyle(.bordered)
            }
            if let src = model.notesSourceName {
                Text(src).font(.caption).foregroundStyle(.tertiary)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .padding(14)
    }
}
