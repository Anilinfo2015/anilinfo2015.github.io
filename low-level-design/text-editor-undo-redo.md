---
title: "LLD Walkthrough: Design a Text Editor with Undo and Redo"
series: "Low-Level Design Interview Playbook"
readingTime: "~22 minutes"
difficulty: Advanced
date: 2026-07-10
topics: ["Low-Level Design", "Text Editor", "Command Pattern", "Memento Pattern", "Rope", "Piece Table", "OOD"]
---

# LLD Walkthrough: Design a Text Editor with Undo and Redo

> Self-contained walkthrough. It designs the undo/redo core of a text editor the way you should in an interview: commands, two stacks, clear mutation ownership, and no detour into building VS Code.

This is a pattern-recognition problem, but not in the shallow sense. The point is not to say "Command pattern" and stop. The point is to make every edit a reversible object, route all document mutations through the editor, and show exactly how redo is invalidated when a new edit arrives.

The trap is the text buffer. Candidates get pulled into gap buffers, ropes, piece tables, Unicode grapheme clusters, and cursor rendering. Name the buffer choice in one line, hide it behind `TextBuffer`, and spend your time on undo/redo behavior.

---

## Minute 0-7: Clarify and fence the scope

Shrink the editor before modeling it:

- **Primary flow?** → Insert text, delete text, undo, redo.
- **Scope of document?** → Single document in memory, no collaborative editing.
- **Selection?** → Support cursor plus optional selection range; formatting is out of scope.
- **Persistence?** → Saving to disk is out of scope; the design focuses on editing state.
- **Buffer implementation?** → Treat it as a `TextBuffer`; mention gap buffer or rope, do not implement it live.

Say the fence out loud:

> "In scope: a single in-memory document, insert/delete edits, cursor/selection updates, undo and redo. Out of scope: rendering, file I/O, syntax highlighting, collaboration, and full Unicode layout. I'll use the Command pattern so every edit knows how to execute and undo itself. OK?"

That scope is small enough to finish and rich enough to show design skill.

Add the senior caveat:

> "The buffer representation matters in a real editor, but it is not the interview's core. I'll hide gap-buffer or rope details behind `TextBuffer` and keep the undo model independent of that choice."

Now you are solving the right problem.

---

## Minute 7-13: Core entities

Start from responsibilities, not from UI widgets.

| Object | Responsibility (one line) |
|---|---|
| `Editor` | Public entry point; converts user actions into commands and updates cursor state. |
| `Document` | Owns the text buffer and document-level metadata. |
| `TextBuffer` | Performs low-level insert/delete operations at positions. |
| `Command` | Reversible edit with `execute()` and `undo()`. |
| `InsertCommand` | Inserts text and can remove exactly what it inserted. |
| `DeleteCommand` | Deletes a range and stores deleted text for undo. |
| `CommandHistory` | Owns undo and redo stacks and enforces redo invalidation. |
| `CursorSelection` | Tracks cursor position and optional selected range. |

Eight objects. Composition, not inheritance: `Editor` has a `Document`, `Document` has a `TextBuffer`, `CommandHistory` has command stacks.

```mermaid
classDiagram
    class Editor
    class Document
    class TextBuffer
    class Command {
        <<interface>>
    }
    class CommandHistory
    class CursorSelection
    Editor --> Document
    Editor --> CommandHistory
    Document --> TextBuffer
    Editor --> CursorSelection
    CommandHistory --> Command
```

Keep `InsertCommand` and `DeleteCommand` off the first diagram if space is tight. Say them verbally. The interface matters more than drawing every concrete command.

---

## Minute 13-20: The spine (API + varying interfaces)

Define the client-facing editor methods:

```text
void insert(String text)
void deleteSelectionOrPreviousChar()
void deleteRange(int start, int end)
void undo()
void redo()
String getText()
```

Now the core interface:

```text
interface Command {
  void execute()
  void undo()
  boolean canMergeWith(Command next)
  Command mergeWith(Command next)   // combine undo metadata of two applied edits
}
```

Name the pattern:

- `Command` is the **Command pattern**. Each edit is an object that knows how to apply and reverse itself.
- `CommandHistory` is not a pattern trophy; it is the owner of two stacks.

Concrete commands:

```text
class InsertCommand implements Command {
  Document doc
  int position
  String text
  CursorSelection before
  CursorSelection after
  execute(): doc.buffer.insert(position, text)
  undo():    doc.buffer.delete(position, position + text.length)
}

class DeleteCommand implements Command {
  Document doc
  int start
  int end
  String deletedText
  CursorSelection before
  CursorSelection after
  execute(): deletedText = doc.buffer.delete(start, end)
  undo():    doc.buffer.insert(start, deletedText)
}
```

`CommandHistory` spine:

```text
class CommandHistory {
  void apply(Command c)   // execute, push undo, clear redo
  void undo()             // pop undo, undo, push redo
  void redo()             // pop redo, execute, push undo
}
```

Say this out loud:

> "All mutations go through commands. If someone edits the buffer directly, undo becomes dishonest, so `TextBuffer` should be package-private or only reachable through `Document` methods used by commands."

That is a staff-level ownership statement.

---

## Minute 20-33: Walk the happy path

Use a tiny sequence diagram for typing one character and undoing it.

```mermaid
sequenceDiagram
    participant U as User
    participant E as Editor
    participant H as History
    participant C as Command
    participant D as Document
    U->>E: insert("a")
    E->>H: apply(InsertCommand)
    H->>C: execute()
    C->>D: insertAt(cursor, "a")
    U->>E: undo()
    E->>H: undo()
    H->>C: undo()
```

Narrate the exact state transitions:

- "Before executing, `InsertCommand` records the cursor/selection state."
- "After executing, it stores the new cursor position so redo can restore the same user-visible state."
- "`CommandHistory.apply` pushes the command onto the undo stack and clears the redo stack."
- "Undo pops from undo, calls `undo()`, and pushes the same command onto redo."

The apply flow:

```text
CommandHistory.apply(command):
  command.execute()          // always execute first
  undoStack.push(command)
  redoStack.clear()          // a new edit invalidates redo
```

That is the whole core: execute, record for undo, and clear redo because branching history is out of scope. Keep *this* as your live answer.

Coalescing (merging rapid keystrokes into one undo unit) is an optimization for the stretch phase. Show it only if asked, and get the ordering right — execute the new command first, then merge, and guard the empty stack:

```text
apply(command):
  command.execute()
  if not undoStack.isEmpty() and undoStack.peek().canMergeWith(command):
    merged = undoStack.pop().mergeWith(command)   // both edits already applied
    undoStack.push(merged)
  else:
    undoStack.push(command)
  redoStack.clear()
```

The subtlety to say out loud: both edits are already applied to the buffer by the time you merge, so `mergeWith` only combines their *undo* metadata (e.g., a single range to delete) — it must not re-apply anything.

Undo/redo:

```text
undo():
  if undoStack.empty(): return
  command = undoStack.pop()
  command.undo()
  redoStack.push(command)

redo():
  if redoStack.empty(): return
  command = redoStack.pop()
  command.execute()
  undoStack.push(command)
```

A state diagram makes redo invalidation obvious:

```mermaid
stateDiagram-v2
    [*] --> CleanHistory
    CleanHistory --> CanUndo: apply(command)
    CanUndo --> CanRedo: undo()
    CanRedo --> CanUndo: redo()
    CanRedo --> CanUndo: new edit clears redo
    CanUndo --> CleanHistory: undo all
```

Walk one concrete delete:

```text
deleteRange(1, 3) on "cats"
  stores deletedText="at"
  execute -> "cs"
  undo -> insert "at" at 1 -> "cats"
```

Say the quiet part:

> "Delete must store the deleted text at execution time. Otherwise undo cannot reconstruct the document after the range is gone."

That sentence usually lands.

---

## Minute 33-42: Stretch and edges

Common curveballs and bounded answers:

- **"Typing every character creates too many undo steps."** Coalesce adjacent `InsertCommand`s typed close together into one undo unit. Use a time window, adjacent positions, and same edit mode. Do not merge across cursor jumps, selection changes, or paste operations.

```text
canMergeWith(next):
  return both inserts
     and this.position + this.text.length == next.position
     and next.timestamp - this.timestamp < 1000ms
```

- **"Redo after a new edit?"** Clear redo on any new command applied after undo. Redo represents an abandoned future; once the user branches, that future is invalid.

- **"Command versus Memento?"** Command stores the inverse operation; memory-cheap for small edits and expressive for operations like delete, paste, replace. **Memento pattern** stores snapshots; simpler and safer for tiny documents or complex operations, but expensive for large documents unless snapshots are incremental.

```text
interface SnapshotStore {
  Snapshot capture(Document d)
  void restore(Document d, Snapshot s)
}
```

- **"Large document?"** Use a rope, piece table, or gap buffer behind `TextBuffer`. The undo model should not care. For huge deletes, `DeleteCommand` storing deleted text is expected; for huge operations, use chunking or snapshots.

- **"Selection delete?"** Convert it to `DeleteCommand(start, end)` and store `CursorSelection before/after`. The command should restore both text and cursor state on undo.

- **"Replace text?"** Either compose `DeleteCommand` + `InsertCommand` into a `CompositeCommand`, or create `ReplaceCommand` that stores old and new text. Composition is cleaner live.

- **"Undo after save?"** Saving is not an undo boundary. Track `lastSavedCommandId` if you need dirty-state detection.

- **"Thread safety?"** Most desktop editors serialize edits on the UI thread. If background tools mutate text, route them through the same command queue. Do not sprinkle locks through commands unless the prompt explicitly asks for concurrent editing.

The anti-pattern to name:

> "I am not going to optimize the rope or handle grapheme clusters live. Those are real editor concerns, but they sit below `TextBuffer`. The LLD signal here is reversible commands and history ownership."

That keeps you out of the rabbit hole.

---

## Minute 42-45: Wrap up

> "The editor has a document with a hidden text buffer, an editor facade that turns user actions into commands, and a `CommandHistory` with undo and redo stacks. Insert and delete are reversible commands. Applying a new command executes it, pushes undo, and clears redo. Undo and redo move the same command between stacks. Coalescing and snapshot alternatives are extensions, not rewrites."

If there is time, name the tests:

```text
- insert then undo restores text and cursor
- delete then undo restores deleted text
- redo reapplies the exact command
- new edit after undo clears redo
- adjacent typing can coalesce into one undo unit
```

End there. More buffer talk will usually make the answer worse.

---

## How real systems solve this

Real editors protect the same invariant as the interview design: every user-visible mutation must pass through one owner that can record undo metadata. The Command pattern fits small edits because each edit carries its inverse: insert can delete the inserted range; delete can store and restore the removed text. Memento is the safer alternative when the operation is complex enough that inverse logic is risky, but snapshots cost more memory unless they are incremental.

The two-stack model is still the core mental model. Applying a command executes it, pushes it onto undo, and clears redo. Undo moves the command to redo after reversing it. Redo executes the same command again and moves it back to undo. A new edit after undo invalidates the abandoned future.

The buffer is where production editors diverge from the naive interview version. A plain string is simple but O(n) for middle inserts and deletes. Gap buffers, ropes, and piece tables keep edits cheaper for large documents; ropes provide O(log n) splits and concatenations, and VS Code has written about using a piece-tree text buffer for performance.

Collaborative editing is a distributed extension, not a bigger undo stack. Systems like Google Docs need Operational Transformation or CRDT-style merging so concurrent inserts and deletes converge across clients. Keep that as a separate synchronization layer above or beside the local command history.

## Reference implementation

This is the core undo/redo mechanism with reversible commands and redo invalidation. The buffer is intentionally a simple list-backed string facade; production storage can replace it behind the same methods.

```python
from dataclasses import dataclass

class TextBuffer:
    def __init__(self, text: str = ""):
        self._chars = list(text)
    def insert(self, pos: int, text: str) -> None:
        self._chars[pos:pos] = list(text)
    def delete(self, start: int, end: int) -> str:
        removed = ''.join(self._chars[start:end])
        del self._chars[start:end]
        return removed

class Command:
    def execute(self) -> None: raise NotImplementedError
    def undo(self) -> None: raise NotImplementedError

@dataclass
class InsertCommand(Command):
    buffer: TextBuffer
    pos: int
    text: str
    def execute(self) -> None: self.buffer.insert(self.pos, self.text)
    def undo(self) -> None: self.buffer.delete(self.pos, self.pos + len(self.text))

@dataclass
class DeleteCommand(Command):
    buffer: TextBuffer
    start: int
    end: int
    removed: str = ""
    def execute(self) -> None: self.removed = self.buffer.delete(self.start, self.end)
    def undo(self) -> None: self.buffer.insert(self.start, self.removed)

class CommandHistory:
    def __init__(self):
        self.undo_stack: list[Command] = []
        self.redo_stack: list[Command] = []
    def apply(self, command: Command) -> None:
        command.execute(); self.undo_stack.append(command); self.redo_stack.clear()
    def undo(self) -> None:
        if self.undo_stack:
            command = self.undo_stack.pop(); command.undo(); self.redo_stack.append(command)
    def redo(self) -> None:
        if self.redo_stack:
            command = self.redo_stack.pop(); command.execute(); self.undo_stack.append(command)
```

## Complexity and trade-offs

| Operation | Naive string/list buffer | Rope/piece-table style buffer | History cost |
|---|---:|---:|---:|
| Insert in middle | O(n) | Often logarithmic or chunk-oriented | Store command metadata |
| Delete range | O(n) | Often logarithmic or chunk-oriented | Store deleted text |
| Undo insert | O(n) with naive buffer | Buffer-dependent | Reuse command |
| Undo delete | O(n) with naive buffer | Buffer-dependent | Reinsert stored text |
| Snapshot undo | O(n) per snapshot | Can be incremental | Simpler restore logic |

- Command is memory-efficient for small edits, but each command must store enough inverse data to be honest.
- Memento snapshots are simpler for complex transformations, but full snapshots are expensive for large documents.
- Buffer choice should be hidden behind `TextBuffer`; undo logic should not know whether storage is a rope, gap buffer, or piece tree.
- Collaborative editing requires OT or CRDTs because local undo/redo does not resolve concurrent remote edits by itself.

## Further reading

- [Command](https://refactoring.guru/design-patterns/command) — core pattern for reversible editor actions.
- [Memento](https://refactoring.guru/design-patterns/memento) — snapshot-based alternative for undo/redo.
- [Rope data structure](https://en.wikipedia.org/wiki/Rope_%28data_structure%29) — background on tree-shaped text buffers with efficient splits and concatenations.
- [Text Buffer Reimplementation in Visual Studio Code](https://code.visualstudio.com/blogs/2018/03/23/text-buffer-reimplementation) — practical piece-tree discussion for large editor buffers.
- *Design Patterns* — GoF — canonical treatment of Command and Memento.

## What separated a pass from a fail here

- You identified the **Command pattern** as the core, then actually used it with `execute()` and `undo()`.
- You kept history honest with **two stacks** and explicit redo invalidation.
- You stored enough inverse data: inserted range, deleted text, and cursor/selection state.
- You mentioned **Memento** as an alternative with a clear trade-off, not as a competing rewrite.
- You avoided the buffer rabbit hole by hiding gap buffer, rope, or piece table behind `TextBuffer`.

That is the whole game: reversible edits, owned mutation, two stacks, bounded buffer talk.
