import SwiftUI
import UniformTypeIdentifiers

/// The presenter-only speaker-notes pane shown beside the slide. It shows either
/// parsed `.tex` notes for the current slide, or — for a "notes on second screen"
/// split PDF — the right-hand notes half of the page.
struct NotesPanel: View {
    @EnvironmentObject var model: PresentationModel
    @State private var importing = false
    @State private var loadFailed = false

    /// `.nav` is offered alongside `.tex`: the picker grants access one file at a
    /// time, so a Beamer deck's page ranges are only readable when the `.nav` is
    /// picked too — without it every frame collapses to one page.
    private var noteTypes: [UTType] {
        [UTType(filenameExtension: "tex"), UTType(filenameExtension: "nav"),
         .plainText, .text, .data].compactMap { $0 }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider().overlay(Theme.hairlineStrong)
            if model.notesSourceName != nil && !model.splitNotes { sourceRow }
            content
        }
        .background(Theme.surface)
        .foregroundStyle(Theme.textPrimary)
        .fileImporter(isPresented: $importing, allowedContentTypes: noteTypes,
                      allowsMultipleSelection: true) { result in
            guard case .success(let urls) = result else { return }
            load(urls)
        }
        .alert("No speaker notes in that file", isPresented: $loadFailed) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("BeamerPresenter reads notes written as \\note{…} in the .tex source. "
                 + "The file you picked has none.")
        }
    }

    /// Takes whichever of the picked files is the `.tex` and which is the `.nav`.
    private func load(_ urls: [URL]) {
        let ext = { (u: URL) in u.pathExtension.lowercased() }
        guard let tex = urls.first(where: { ext($0) == "tex" }) ?? urls.first else { return }
        let nav = urls.first { ext($0) == "nav" }
        if !model.loadTexNotes(url: tex, navURL: nav) { loadFailed = true }
    }

    private var header: some View {
        HStack {
            Text("Speaker notes").font(.mono(9)).textCase(.uppercase).tracking(1.6)
                .foregroundStyle(Theme.textMuted)
            Spacer()
            Text(String(format: "%02d / %02d", model.index + 1, model.pageCount))
                .font(.mono(11)).foregroundStyle(Theme.textMuted)
            // Always reachable, not only while the pane is empty: notes read from
            // the wrong file, or from a .tex without its .nav, have to be
            // replaceable without reopening the deck.
            if !model.splitNotes {
                Menu {
                    Button { importing = true } label: {
                        Label(model.notesByPage.isEmpty ? "Load notes (.tex)…"
                                                        : "Load different notes…",
                              systemImage: "doc.text")
                    }
                    if model.notesSourceName != nil {
                        Button(role: .destructive) { model.clearNotes() } label: {
                            Label("Clear notes", systemImage: "trash")
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis.circle").font(.system(size: 14))
                        .foregroundStyle(Theme.textMuted)
                }
                .accessibilityLabel("Notes options")
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
    }

    /// Where the notes came from, and whether their slide positions are exact.
    private var sourceRow: some View {
        HStack(spacing: 6) {
            Image(systemName: model.notesExact ? "doc.text" : "exclamationmark.triangle")
                .font(.system(size: 10))
            Text(model.notesSourceName ?? "").lineLimit(1).truncationMode(.middle)
            if !model.notesExact {
                Text("· one page per frame — pick the .nav too for overlay decks")
                    .lineLimit(2)
            }
            Spacer()
        }
        .font(.caption)
        .foregroundStyle(model.notesExact ? Theme.textMuted : Theme.statusWarn)
        .padding(.horizontal, 14).padding(.vertical, 6)
        .background(Theme.raised)
    }

    @ViewBuilder
    private var content: some View {
        if model.splitNotes {
            PDFPageView(document: model.document, pageIndex: model.index,
                        displayBox: .trimBox)
                .padding(8)
        } else if let note = model.note(for: model.index), !note.isEmpty {
            ScrollView {
                Text(NotesMarkup.attributed(note, size: 17))
                    .lineSpacing(5)
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
                Button { importing = true } label: {
                    Label("Load notes (.tex)…", systemImage: "doc.text")
                }
                .buttonStyle(.bordered)
                Text("Pick the .tex and its .nav together for a deck that uses overlays.")
                    .font(.caption).foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .padding(14)
    }
}
