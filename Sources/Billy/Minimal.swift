import SwiftUI

/// The notch's look, for the projects window and its sheets: black, white at a few opacities, hairlines.
enum Ink {
    static let primary = Color.white.opacity(0.9)
    static let secondary = Color.white.opacity(0.5)
    static let tertiary = Color.white.opacity(0.3)
    static let fill = Color.white.opacity(0.06)
    static let selection = Color.white.opacity(0.1)
    static let line = Color.white.opacity(0.07)

    static let body = Font.system(size: 13)
    static let caption = Font.system(size: 11, weight: .semibold)
    static func number(_ size: CGFloat = 13, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .rounded).monospacedDigit()
    }
}

struct Hairline: View {
    var vertical = false

    var body: some View {
        Rectangle().fill(Ink.line)
            .frame(width: vertical ? 1 : nil, height: vertical ? nil : 1)
    }
}

/// A small caption above a group of rows.
struct Caption: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(Ink.caption)
            .foregroundStyle(Ink.tertiary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 20)
            .padding(.bottom, 4)
    }
}

/// Label on the left, control on the right, hairline under.
struct FieldRow<Content: View>: View {
    let label: String
    @ViewBuilder let content: Content

    init(_ label: String, @ViewBuilder content: () -> Content) {
        self.label = label
        self.content = content()
    }

    var body: some View {
        HStack(spacing: 16) {
            Text(label)
                .foregroundStyle(Ink.secondary)
                .fixedSize()
            Spacer(minLength: 0)
            content
                .foregroundStyle(Ink.primary)
        }
        .font(Ink.body)
        .frame(minHeight: 34)
        .overlay(alignment: .bottom) { Hairline() }
    }
}

/// A plain right-aligned text field for `FieldRow`.
struct InlineField: View {
    let placeholder: String
    @Binding var text: String

    init(_ placeholder: String = "", text: Binding<String>) {
        self.placeholder = placeholder
        _text = text
    }

    var body: some View {
        TextField(placeholder, text: $text)
            .textFieldStyle(.plain)
            .multilineTextAlignment(.trailing)
    }
}

struct InlineNumberField: View {
    let placeholder: String
    @Binding var value: Double

    var body: some View {
        TextField(placeholder, value: $value, format: .number)
            .textFieldStyle(.plain)
            .multilineTextAlignment(.trailing)
            .font(Ink.number())
    }
}

/// A capsule button. `prominent` is white with black text, as for the one main action.
struct PillStyle: ButtonStyle {
    var prominent = false
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(prominent ? Color.black : Ink.primary)
            .padding(.horizontal, 14)
            .frame(height: 28)
            .background(prominent ? Color.white.opacity(0.92) : Color.white.opacity(0.1), in: Capsule())
            .contentShape(Capsule())
            .scaleEffect(configuration.isPressed ? 0.95 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
            .opacity(isEnabled ? 1 : 0.35)
    }
}

/// A borderless icon button.
struct IconStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(configuration.isPressed ? Ink.primary : Ink.secondary)
            .frame(width: 28, height: 28)
            .contentShape(Rectangle())
            .opacity(isEnabled ? 1 : 0.35)
    }
}

/// A capsule segmented control.
struct Segments<Value: Hashable>: View {
    let options: [(Value, String)]
    @Binding var selection: Value
    @Namespace private var ns

    var body: some View {
        HStack(spacing: 2) {
            ForEach(options, id: \.0) { value, title in
                Button { withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) { selection = value } } label: {
                    Text(title)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(selection == value ? Ink.primary : Ink.secondary)
                        .padding(.horizontal, 12)
                        .frame(height: 24)
                        .background {
                            if selection == value {
                                Capsule().fill(Color.white.opacity(0.14))
                                    .matchedGeometryEffect(id: "selection", in: ns)
                            }
                        }
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(2)
        .background(Ink.fill, in: Capsule())
        .fixedSize()
    }
}

/// A menu that looks like plain text with a chevron, for choosing inside a `FieldRow`.
struct InlineMenu<Value: Hashable>: View {
    let options: [(Value, String)]
    @Binding var selection: Value

    var body: some View {
        Menu {
            ForEach(options, id: \.0) { value, title in
                Button(title) { selection = value }
            }
        } label: {
            HStack(spacing: 4) {
                Text(options.first { $0.0 == selection }?.1 ?? "")
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(Ink.tertiary)
            }
            .foregroundStyle(Ink.primary)
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
    }
}

/// A sheet's black canvas with a title and a bottom row of buttons.
struct SheetChrome<Content: View, Buttons: View>: View {
    let title: String
    @ViewBuilder let content: Content
    @ViewBuilder let buttons: Buttons

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Ink.primary)
                .padding(.bottom, 4)
            content
            HStack(spacing: 8) {
                Spacer()
                buttons
            }
            .padding(.top, 24)
        }
        .padding(24)
        .background(Color.black)
        .environment(\.colorScheme, .dark)
    }
}

extension View {
    /// Stops a text field accepting more than `max` characters.
    func limit(_ text: Binding<String>, to max: Int) -> some View {
        onChange(of: text.wrappedValue) { _, new in
            if new.count > max { text.wrappedValue = String(new.prefix(max)) }
        }
    }
}

/// A month calendar in the notch style. Click a day, or use the arrow keys and Return.
struct MonthCalendar: View {
    @Binding var selection: Date
    var onPick: () -> Void = {}

    @State private var month: Date
    @State private var hovered: Date?
    @State private var direction = 1
    @FocusState private var focused: Bool

    private static let cell: CGFloat = 40
    private var cal: Calendar { Calendar.current }

    init(selection: Binding<Date>, onPick: @escaping () -> Void = {}) {
        _selection = selection
        self.onPick = onPick
        _month = State(initialValue: Calendar.current.dateInterval(of: .month, for: selection.wrappedValue)?.start
                       ?? selection.wrappedValue)
    }

    var body: some View {
        VStack(spacing: 14) {
            header
            VStack(spacing: 6) {
                weekdays
                grid
                    .id(month)
                    .transition(.asymmetric(insertion: .move(edge: direction > 0 ? .trailing : .leading).combined(with: .opacity),
                                            removal: .opacity))
            }
            .clipped()
            HStack(spacing: 8) {
                Button("Today") { pick(cal.startOfDay(for: .now)) }
                    .buttonStyle(PillStyle())
                Button("Yesterday") { pick(cal.date(byAdding: .day, value: -1, to: cal.startOfDay(for: .now)) ?? .now) }
                    .buttonStyle(PillStyle())
                Spacer()
            }
        }
        .padding(18)
        .frame(width: Self.cell * 7 + 36)
        .background(Color.black)
        .environment(\.colorScheme, .dark)
        .focusable()
        .focusEffectDisabled()
        .focused($focused)
        .onAppear { focused = true }
        .onKeyPress(.leftArrow) { move(days: -1) }
        .onKeyPress(.rightArrow) { move(days: 1) }
        .onKeyPress(.upArrow) { move(days: -7) }
        .onKeyPress(.downArrow) { move(days: 7) }
        .onKeyPress(.return) { onPick(); return .handled }
    }

    private var header: some View {
        HStack {
            Text(month.formatted(.dateTime.month(.wide).year()))
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Ink.primary)
                .contentTransition(.numericText())
            Spacer()
            Button { shift(-1) } label: { Image(systemName: "chevron.left") }
            Button { shift(1) } label: { Image(systemName: "chevron.right") }
        }
        .buttonStyle(IconStyle())
        .padding(.leading, 6)
    }

    private var weekdays: some View {
        let symbols = cal.veryShortStandaloneWeekdaySymbols
        let first = cal.firstWeekday - 1
        return HStack(spacing: 0) {
            ForEach(0..<7, id: \.self) { i in
                Text(symbols[(first + i) % 7])
                    .font(Ink.caption)
                    .foregroundStyle(Ink.tertiary)
                    .frame(width: Self.cell)
            }
        }
    }

    /// Six full weeks, starting on the week that holds the 1st.
    private var days: [Date] {
        let start = cal.dateInterval(of: .weekOfYear, for: month)?.start ?? month
        return (0..<42).compactMap { cal.date(byAdding: .day, value: $0, to: start) }
    }

    private var grid: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.fixed(Self.cell), spacing: 0), count: 7), spacing: 2) {
            ForEach(days, id: \.self) { day in
                dayCell(day)
            }
        }
    }

    private func dayCell(_ day: Date) -> some View {
        let selected = cal.isDate(day, inSameDayAs: selection)
        let today = cal.isDateInToday(day)
        let inMonth = cal.isDate(day, equalTo: month, toGranularity: .month)
        let isHovered = hovered.map { cal.isDate($0, inSameDayAs: day) } ?? false

        return Text("\(cal.component(.day, from: day))")
            .font(Ink.number(14, weight: selected || today ? .semibold : .medium))
            .foregroundStyle(selected ? Color.black : inMonth ? Ink.primary : Color.white.opacity(0.18))
            .frame(width: Self.cell - 6, height: Self.cell - 6)
            .background {
                Circle().fill(selected ? Color.white.opacity(0.92) : isHovered ? Ink.selection : .clear)
            }
            .overlay {
                if today && !selected {
                    Circle().strokeBorder(Color.white.opacity(0.35), lineWidth: 1)
                }
            }
            .frame(width: Self.cell, height: Self.cell)
            .contentShape(Rectangle())
            .onHover { hovered = $0 ? day : (isHovered ? nil : hovered) }
            .onTapGesture { pick(day) }
            .animation(.easeOut(duration: 0.12), value: selected)
    }

    // MARK: Actions

    private func pick(_ day: Date) {
        select(day)
        onPick()
    }

    /// Changes the day but keeps the time of day already chosen.
    private func select(_ day: Date) {
        let time = cal.dateComponents([.hour, .minute, .second], from: selection)
        selection = cal.date(bySettingHour: time.hour ?? 0, minute: time.minute ?? 0, second: time.second ?? 0,
                             of: cal.startOfDay(for: day)) ?? day
        if !cal.isDate(day, equalTo: month, toGranularity: .month) {
            show(cal.dateInterval(of: .month, for: day)?.start ?? day)
        }
    }

    private func shift(_ months: Int) {
        if let m = cal.date(byAdding: .month, value: months, to: month) { show(m) }
    }

    private func show(_ newMonth: Date) {
        direction = newMonth > month ? 1 : -1
        withAnimation(.spring(response: 0.32, dampingFraction: 0.88)) { month = newMonth }
    }

    private func move(days: Int) -> KeyPress.Result {
        if let d = cal.date(byAdding: .day, value: days, to: selection) { select(d) }
        return .handled
    }
}
