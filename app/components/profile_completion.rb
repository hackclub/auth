class Components::ProfileCompletion < ApplicationComponent
  def initialize(identity:)
    @identity = identity
  end

  def tasks
    @tasks ||= build_tasks
  end

  def build_tasks
    tasks = []
    
    # Verification task
    verification_item = Components::VerificationStatusItem.new(identity: @identity)
    if verification_item.show?
      tasks << {
        component: verification_item
      }
    end

    tasks << {
      title: I18n.t("home.completion_tasks.phone_number.title"),
      description: I18n.t("home.completion_tasks.phone_number.description"),
      completed: @identity.phone_number.present?,
      url: -> { edit_identity_path },
      icon: "message"
    }

    tasks << {
      title: I18n.t("home.completion_tasks.mailing_address.title"),
      description: I18n.t("home.completion_tasks.mailing_address.description"),
      completed: @identity.primary_address_id.present?,
      url: -> { new_address_path },
      icon: "email"
    }

    # Sort tasks: completed ones first (bubbled to top)
    tasks.sort_by do |task|
      if task[:component]
        task[:component].completed? ? 0 : 1
      else
        task[:completed] ? 0 : 1
      end
    end
  end

  def completed_count
    tasks.count do |task|
      if task[:component]
        task[:component].completed?
      else
        task[:completed]
      end
    end
  end

  def total_count = tasks.count

  def progress_percentage = (completed_count.to_f / total_count * 100).round

  def show? = completed_count < total_count

  def view_template
    div(class: "profile-completion") do
      div(class: "profile-completion-header") do
        div(class: "header-content") do
          h2 { t "home.completion_tasks.complete_your_profile" }
          div(class: "completion-stats") do
            span(class: "stats-text") { "#{completed_count} of #{total_count} complete" }
          end
        end
        div(class: "progress-bar-container") do
          div(class: "progress-bar", style: "width: #{progress_percentage}%")
        end
      end

      div(class: "profile-tasks") do
        tasks.each do |task|
          # Handle component-based tasks
          if task[:component]
            render task[:component]
            next
          end

          # Handle regular tasks - show all tasks, style differently based on completion
          task_classes = ["profile-task"]
          task_classes << "completed" if task[:completed]

          a(href: task[:url].call, class: task_classes.join(" ")) do
            div(class: "task-icon") { helpers.inline_icon(task[:icon], size: 24) }
            div(class: "task-content") do
              div(class: "task-title") { task[:title] }
              div(class: "task-description") { task[:description] }
            end
            div(class: "task-action") { task[:completed] ? helpers.inline_icon("check", size: 16) : "→" }
          end
        end
      end
    end
  end
end
