require "crysterm"
require "../manager"

module GoogleApis
  module Tui
    alias CT = Crysterm
    alias CW = CT::Widgets

    # Crysterm-based Terminal User Interface for Google APIs client library.
    class App
      getter window : CT::Window
      getter project_root : String
      getter menu_list : CW::List
      getter log_view : CW::Log
      getter status_bar : CW::Box

      MENU_ITEMS = [
        "[G] Generate API (Choose Target)",
        "[L] Show All Discovery Targets",
        "[D] Generate Documentation (crystal docs)",
        "[R] Remove Generated Documentation",
        "[T] Run Tests for Particular API",
        "[A] Run All Unit Tests",
        "[C] Clear & Regenerate APIs",
        "[S] Save / Sync api-list.yaml",
        "[H] Print Help",
        "[Q] Quit",
      ]

      def initialize(@project_root : String = ".")
        # Ensure sane terminal environment
        if ENV["TERM"]?.try(&.in?("", "dumb")) || ENV["TERM"]?.nil?
          ENV["TERM"] = "xterm-256color"
        end

        CT::Config.set "screen.border_junctions", true

        @window = CT::Window.new title: "Google APIs Generator & Manager"

        # Header bar
        header = CW::Box.new(
          parent: @window,
          top: 0,
          left: 0,
          width: "100%",
          height: 3,
          parse_tags: true,
          style: CT::Style.new(border: true)
        )
        header.content = "{center}{bold}{#57c7ff-fg}Google APIs Crystal Client Generator & Manager{/#57c7ff-fg}{/bold}  (Powered by Crysterm){/center}"

        # Menu Panel
        menu_box = CW::GroupBox.new(
          parent: @window,
          top: 3,
          left: 0,
          width: 44,
          bottom: 2,
          title: " Menu Options "
        )

        @menu_list = CW::List.new(
          parent: menu_box,
          top: 1,
          left: 1,
          right: 1,
          bottom: 1,
          items: MENU_ITEMS
        )

        # Output / Log Panel
        output_box = CW::GroupBox.new(
          parent: @window,
          top: 3,
          left: 44,
          right: 0,
          bottom: 2,
          title: " Activity Log & Output "
        )

        @log_view = CW::Log.new(
          parent: output_box,
          top: 1,
          left: 1,
          right: 1,
          bottom: 1,
          parse_tags: true,
          timestamps: true
        )

        # Status Bar
        @status_bar = CW::Box.new(
          parent: @window,
          bottom: 0,
          left: 0,
          width: "100%",
          height: 2,
          parse_tags: true,
          content: " [Enter] Run Selected  [G] Gen  [L] List  [D] Docs  [R] Clean Docs  [T] Test  [A] All  [C] Regen  [S] Sync  [Q] Quit"
        )

        wire_events
        log_welcome
      end

      private def log_welcome
        @log_view.info "Welcome to Google APIs Crystal Generator TUI!"
        @log_view.info "Use Up/Down arrows to navigate menu, Enter to execute option."
        @log_view.info "Or press shortcut keys: [G], [L], [D], [R], [T], [A], [C], [S], [H], [Q]"

        # Quick check for out of date APIs
        check_outdated_status
      end

      private def check_outdated_status
        registry = ApiListRegistry.load(File.join(@project_root, "api-list.yaml"))
        outdated = registry.out_of_date_apis
        if outdated.empty?
          @log_view.info "API Version Status: All generated APIs are up to date."
        else
          @log_view.warn "Notice: #{outdated.size} generated API(s) may be OUT OF DATE with latest Discovery Docs:"
          outdated.each do |name, entry|
            @log_view.warn "  * #{name}: generated #{entry.generated_version} -> latest #{entry.latest_version}"
          end
        end
      end

      private def wire_events
        # Enter on menu list item
        @menu_list.on(CT::Event::ItemActivated) do |e|
          execute_menu_action(e.index)
        end

        # Global key presses
        @window.on(CT::Event::KeyPress) do |e|
          handle_key_press(e.char)
        end
      end

      private def handle_key_press(char : Char?)
        return unless char
        case char.downcase
        when 'q' then @window.quit
        when 'g' then prompt_generate_api
        when 'l' then show_all_targets
        when 'd' then generate_documentation
        when 'r' then remove_documentation
        else
          handle_secondary_key_press(char.downcase)
        end
      end

      private def handle_secondary_key_press(char : Char)
        case char
        when 't'      then prompt_run_tests
        when 'a'      then run_all_unit_tests
        when 'c'      then clear_and_regenerate
        when 's'      then sync_api_list_yaml
        when 'h', '?' then print_help
        end
      end

      # Handles activation by index
      def execute_menu_action(index : Int32)
        if index < 5
          execute_primary_menu_action(index)
        else
          execute_secondary_menu_action(index)
        end
      end

      private def execute_primary_menu_action(index : Int32)
        case index
        when 0 then prompt_generate_api
        when 1 then show_all_targets
        when 2 then generate_documentation
        when 3 then remove_documentation
        when 4 then prompt_run_tests
        end
      end

      private def execute_secondary_menu_action(index : Int32)
        case index
        when 5 then run_all_unit_tests
        when 6 then clear_and_regenerate
        when 7 then sync_api_list_yaml
        when 8 then print_help
        when 9 then @window.quit
        end
      end

      # Action 1: Prompt user for API to generate
      def prompt_generate_api
        @log_view.info "Enter API name or ID to generate (e.g. storage, run, or path):"
        CW::InputDialog.read(@window, "Generate API (name, ID or discovery JSON path):") do |input|
          if input && !input.strip.empty?
            perform_generation(input.strip)
          else
            @log_view.info "API generation cancelled."
          end
        end
      end

      # Executes generation
      def perform_generation(target_query : String)
        @log_view.info "Generating client for '#{target_query}'..."
        @status_bar.content = " Status: Generating #{target_query}..."
        @window.update

        success, msg, _ = Manager.generate_api(target_query, @project_root)
        if success
          @log_view.info msg
          @status_bar.content = " Status: Successfully generated #{target_query}!"
        else
          @log_view.error msg
          @status_bar.content = " Status: Generation failed for #{target_query}."
        end
        @window.update
      end

      # Action 2: Show all API targets from Discovery Docs
      def show_all_targets
        @log_view.info "Fetching and scanning Google Discovery Document targets..."
        @status_bar.content = " Status: Loading discovery catalog..."
        @window.update

        targets = Manager.list_targets(allow_network: true)
        @log_view.info "Total Discovery targets found: #{targets.size}"

        # Sync api-list.yaml
        Manager.sync_api_list_yaml(@project_root)

        # Print targets
        @log_view.info "--- Discovery API Targets ---"
        targets.first(25).each do |target|
          tag_color = if target.out_of_date?
                        "yellow"
                      elsif target.generated?
                        "green"
                      else
                        "blue"
                      end
          @log_view.info "{#{tag_color}-fg}#{target.status_label}{/#{tag_color}-fg} #{target.id} - #{target.title}"
        end

        if targets.size > 25
          @log_view.info "... and #{targets.size - 25} more targets available (saved to api-list.yaml)."
        end

        @status_bar.content = " Status: Listed #{targets.size} Discovery targets. api-list.yaml updated."
        @window.update
      end

      # Action 3: Generate documentation using `crystal docs`
      def generate_documentation
        @log_view.info "Running `crystal docs` to generate documentation..."
        @status_bar.content = " Status: Running crystal docs..."
        @window.update

        success, msg = Manager.generate_docs(@project_root)
        if success
          @log_view.info msg
          @status_bar.content = " Status: Documentation generated successfully in docs/."
        else
          @log_view.error msg
          @status_bar.content = " Status: Documentation generation failed."
        end
        @window.update
      end

      # Action 4: Remove generated documentation
      def remove_documentation
        @log_view.info "Removing generated documentation directory..."
        success, msg = Manager.remove_docs(@project_root)
        if success
          @log_view.info msg
          @status_bar.content = " Status: Documentation cleaned up."
        else
          @log_view.error msg
          @status_bar.content = " Status: Failed to remove documentation."
        end
        @window.update
      end

      # Action 5: Run unit tests for particular API
      def prompt_run_tests
        generated = Manager.find_generated_api_names(@project_root)
        hint = generated.empty? ? "storage, run" : generated.join(", ")
        @log_view.info "Enter API to test (#{hint}):"

        CW::InputDialog.read(@window, "API to test (#{hint}):") do |input|
          if input && !input.strip.empty?
            perform_test_run(input.strip)
          else
            @log_view.info "Test execution cancelled."
          end
        end
      end

      private def perform_test_run(api_name : String)
        @log_view.info "Running unit tests for '#{api_name}'..."
        @status_bar.content = " Status: Testing #{api_name}..."
        @window.update

        success, output = Manager.run_tests_for(api_name, @project_root)
        if success
          @log_view.info "=== Tests Passed for #{api_name} ==="
          output.each_line { |line| @log_view.info "  #{line}" }
          @status_bar.content = " Status: Tests passed for #{api_name}!"
        else
          @log_view.error "=== Tests Failed for #{api_name} ==="
          output.each_line { |line| @log_view.error "  #{line}" }
          @status_bar.content = " Status: Tests failed for #{api_name}."
        end
        @window.update
      end

      # Action 6: Run all tests
      def run_all_unit_tests
        @log_view.info "Running all unit tests (`crystal spec`)..."
        @status_bar.content = " Status: Running crystal spec..."
        @window.update

        success, output = Manager.run_all_tests(@project_root)
        if success
          @log_view.info "=== All Tests Passed! ==="
          output.each_line { |line| @log_view.info "  #{line}" }
          @status_bar.content = " Status: All unit tests passed!"
        else
          @log_view.error "=== Unit Test Failures ==="
          output.each_line { |line| @log_view.error "  #{line}" }
          @status_bar.content = " Status: Unit tests reported errors."
        end
        @window.update
      end

      # Action 7: Clear out existing generated APIs and regenerate them
      def clear_and_regenerate
        @log_view.warn "Clearing existing generated APIs and regenerating from discovery docs..."
        @status_bar.content = " Status: Regenerating APIs..."
        @window.update

        success, msg = Manager.clear_and_regenerate(@project_root)
        if success
          @log_view.info msg
          @status_bar.content = " Status: APIs successfully regenerated!"
        else
          @log_view.warn msg
          @status_bar.content = " Status: API regeneration completed with warnings."
        end
        @window.update
      end

      # Action 8: Sync Discovery Docs versions to api-list.yaml
      def sync_api_list_yaml
        @log_view.info "Synchronizing latest Discovery versions to api-list.yaml..."
        @status_bar.content = " Status: Syncing api-list.yaml..."
        @window.update

        success, msg = Manager.sync_api_list_yaml(@project_root)
        if success
          @log_view.info msg
          @status_bar.content = " Status: api-list.yaml successfully synchronized."
        else
          @log_view.error msg
          @status_bar.content = " Status: Failed to sync api-list.yaml."
        end
        @window.update
      end

      # Action 9: Print help
      def print_help
        @log_view.info "--- Help & Usage ---"
        Manager.help_text.each_line do |line|
          @log_view.info line
        end
        @status_bar.content = " Status: Help displayed."
        @window.update
      end

      # Starts the TUI main loop
      def run
        @window.exec
      end
    end
  end
end
