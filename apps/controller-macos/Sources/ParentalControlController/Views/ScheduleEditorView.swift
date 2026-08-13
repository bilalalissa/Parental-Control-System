import SwiftUI

struct ScheduleEditorView: View {
  let store: ControllerStore

  var body: some View {
    @Bindable var store = store

    ScrollView {
      VStack(alignment: .leading, spacing: 20) {
        ScreenHeader(
          title: "Schedule preview",
          subtitle: "Validate a local draft before policy transport and enforcement exist."
        )

        SectionCard {
          VStack(alignment: .leading, spacing: 14) {
            Text("Daily limits")
              .font(.headline)

            HStack {
              Text("Daily active-use quota")
              Spacer()
              Stepper(
                "\(store.schedule.dailyQuotaMinutes) minutes",
                value: $store.schedule.dailyQuotaMinutes,
                in: 15...1440,
                step: 15
              )
              .accessibilityIdentifier(AccessibilityID.scheduleQuota.rawValue)
            }

            HStack {
              Text("Warning before restriction")
              Spacer()
              Stepper(
                "\(store.schedule.warningMinutes) minutes",
                value: $store.schedule.warningMinutes,
                in: 1...60
              )
            }

            Picker("Default restriction", selection: $store.schedule.action) {
              ForEach(RestrictionAction.allCases) { action in
                Text(action.title).tag(action)
              }
            }
            .help("Lock is the safe default. Shutdown is never implied or forced.")

            LabeledContent("Time zone", value: store.schedule.timezone)
          }
        }

        SectionCard {
          VStack(alignment: .leading, spacing: 12) {
            Text("Weekly allowed windows")
              .font(.headline)
            Text(
              "An end time earlier than its start crosses midnight. Overlapping windows are rejected."
            )
            .font(.caption)
            .foregroundStyle(.secondary)

            Divider()

            ForEach($store.schedule.windows) { $window in
              WeeklyWindowRow(window: $window)
              if window.id != store.schedule.windows.last?.id {
                Divider()
              }
            }
          }
        }

        if !store.scheduleIssues.isEmpty {
          SectionCard {
            VStack(alignment: .leading, spacing: 8) {
              Label("Schedule needs attention", systemImage: "exclamationmark.triangle.fill")
                .font(.headline)
                .foregroundStyle(.orange)
              ForEach(Array(store.scheduleIssues.enumerated()), id: \.offset) { _, issue in
                Text("• \(issue.message)")
                  .foregroundStyle(.secondary)
              }
            }
          }
        }

        HStack {
          Label(store.scheduleStatusMessage, systemImage: "internaldrive")
            .font(.callout)
            .foregroundStyle(.secondary)
          Spacer()
          Button("Validate and Save Preview") {
            store.validateAndSaveSchedule()
          }
          .buttonStyle(.borderedProminent)
          .accessibilityIdentifier(AccessibilityID.scheduleSave.rawValue)
        }
      }
      .padding(24)
    }
    .navigationTitle("Schedule")
    .accessibilityIdentifier(AccessibilityID.schedule.rawValue)
  }
}

private struct WeeklyWindowRow: View {
  @Binding var window: WeeklyWindow

  var body: some View {
    HStack(spacing: 14) {
      Toggle(window.day.title, isOn: $window.isEnabled)
        .toggleStyle(.switch)
        .frame(width: 155, alignment: .leading)

      TimePicker(label: "From", minute: $window.startMinute)
        .disabled(!window.isEnabled)
      TimePicker(label: "To", minute: $window.endMinute)
        .disabled(!window.isEnabled)
      Spacer()
      if window.isEnabled && window.endMinute <= window.startMinute {
        Text("Next day")
          .font(.caption.weight(.medium))
          .foregroundStyle(.blue)
      }
    }
    .padding(.vertical, 2)
  }
}

private struct TimePicker: View {
  let label: String
  @Binding var minute: Int

  private var date: Binding<Date> {
    Binding(
      get: {
        Calendar.current.date(
          from: DateComponents(year: 2001, month: 1, day: 1, hour: minute / 60, minute: minute % 60)
        ) ?? Date(timeIntervalSinceReferenceDate: 0)
      },
      set: { newValue in
        let components = Calendar.current.dateComponents([.hour, .minute], from: newValue)
        minute = (components.hour ?? 0) * 60 + (components.minute ?? 0)
      }
    )
  }

  var body: some View {
    DatePicker(label, selection: date, displayedComponents: .hourAndMinute)
      .labelsHidden()
      .accessibilityLabel(label)
  }
}
