require "crysterm"
require "../manager"

module GoogleApis
  module Tui
    alias CT = Crysterm
    alias CW = CT::Widgets

    # Crysterm-based Terminal User Interface for Google APIs client library.
    class App
      enum FocusPane
        Menu
        ApiList
      end

      getter window : CT::Window
      getter project_root : String
      getter menu_box : CW::GroupBox
      getter menu_list : CW::List
      getter api_box : CW::GroupBox
      getter api_list : CW::List
      getter output_box : CW::GroupBox
      getter log_view : CW::Log
      getter status_bar : CW::Box
      property active_pane : FocusPane = FocusPane::Menu
      getter targets : Array(DiscoveryTarget)

      MENU_ITEMS = [
        "[G] Generate API (Choose Target)",
        "[D] Generate Documentation (crystal docs)",
        "[R] Remove API and documentation",
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

        CT::Config.set "window.border_junctions", true

        @window = CT::Window.new title: "Google APIs Generator & Manager"
        @targets = [] of DiscoveryTarget
        load_targets

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

        # Menu Panel (Left side)
        @menu_box = CW::GroupBox.new(
          parent: @window,
          top: 3,
          left: 0,
          width: 44,
          bottom: 2,
          title: " Menu Options [Active] "
        )

        @menu_list = CW::List.new(
          parent: @menu_box,
          top: 1,
          left: 1,
          right: 1,
          bottom: 1,
          items: MENU_ITEMS,
          mouse: true,
          vi_keys: true,
          styles: CT::Styles.new(
            selected: CT::Style.new(bg: "blue", fg: "white", bold: true),
          )
        )

        # API Targets Panel (Right side, upper half above log output)
        @api_box = CW::GroupBox.new(
          parent: @window,
          top: 3,
          left: 44,
          right: 0,
          height: "48%",
          title: " Available Google APIs (Press [G] to Highlight) "
        )

        @api_list = CW::List.new(
          parent: @api_box,
          top: 1,
          left: 1,
          right: 1,
          bottom: 1,
          items: @targets.map { |target| target_item_label(target) },
          mouse: true,
          vi_keys: true,
          styles: CT::Styles.new(
            selected: CT::Style.new(bg: "blue", fg: "white", bold: true),
          )
        )

        # Output / Log Panel (Right side, lower half below API list)
        @output_box = CW::GroupBox.new(
          parent: @window,
          top: "48%+3",
          left: 44,
          right: 0,
          bottom: 2,
          title: " Activity Log & Output "
        )

        @log_view = CW::Log.new(
          parent: @output_box,
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
          content: " [↑/↓] Navigate  [Enter] Select  [G] Choose API  [D] Docs  [R] Remove API  [T] Test  [A] All  [C] Regen  [S] Sync  [Q] Quit"
        )

        wire_events
        log_welcome
        @menu_list.focus
      end

      private def load_targets
        @targets = Manager.list_targets(allow_network: false)
        if @targets.empty?
          @targets = Manager.list_targets(allow_network: true)
        end
        @targets.sort_by! { |target| {target.generated? ? 0 : 1, target.id} }
      end

      private def target_item_label(target : DiscoveryTarget) : String
        status = target.generated? ? "[INSTALLED]" : "[AVAILABLE]"
        "#{status.ljust(12)} #{target.id.ljust(22)} #{target.title}"
      end

      def refresh_targets_list
        load_targets
        @api_list.items = @targets.map { |target| target_item_label(target) }
      end

      private def log_welcome
        @log_view.info "Welcome to Google APIs Crystal Generator TUI!"
        @log_view.info "Use Up/Down arrows to navigate menu, Enter to execute option."
        @log_view.info "Press [G] to choose and install an API from the catalog list above."
        @log_view.info "Shortcuts: [G] Choose API, [D] Docs, [R] Remove API, [T] Test, [Q] Quit"

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

        # Enter on API target item
        @api_list.on(CT::Event::ItemActivated) do |e|
          generate_selected_api(e.index)
        end

        # Cancel on API list (Escape)
        @api_list.on(CT::Event::ItemCancelled) do |_e|
          return_to_menu
        end

        # Focus synchronization
        @menu_list.on(CT::Event::FocusIn) do |_e|
          @active_pane = FocusPane::Menu
          update_focus_ui
          @window.update
        end

        @api_list.on(CT::Event::FocusIn) do |_e|
          @active_pane = FocusPane::ApiList
          update_focus_ui
          @window.update
        end

        # Global key presses
        @window.on(CT::Event::KeyPress) do |e|
          handle_key_press(e)
        end
      end

      private def handle_key_press(e : CT::Event::KeyPress)
        return if @window.grab_keys?
        return if handle_arrow_keys(e)
        return if handle_action_keys(e)
        return if e.accepted?

        char = e.char
        return unless char
        handle_char_keys(char.downcase)
      end

      private def handle_arrow_keys(e : CT::Event::KeyPress) : Bool
        case e.key
        when ::Tput::Key::Up
          unless e.accepted?
            @active_pane.api_list? ? @api_list.up : @menu_list.up
            @window.update
          end
          true
        when ::Tput::Key::Down
          unless e.accepted?
            @active_pane.api_list? ? @api_list.down : @menu_list.down
            @window.update
          end
          true
        else
          false
        end
      end

      private def handle_action_keys(e : CT::Event::KeyPress) : Bool
        case e.key
        when ::Tput::Key::Enter
          unless e.accepted?
            if @active_pane.api_list?
              generate_selected_api(@api_list.current_index)
            else
              execute_menu_action(@menu_list.current_index)
            end
          end
          true
        when ::Tput::Key::Escape, ::Tput::Key::Left
          return false unless @active_pane.api_list?
          return_to_menu
          true
        when ::Tput::Key::Right
          return false unless @active_pane.menu?
          start_api_selection
          true
        when ::Tput::Key::Tab
          @active_pane.menu? ? start_api_selection : return_to_menu
          true
        else
          false
        end
      end

      private def handle_char_keys(char : Char)
        case char
        when 'q' then @window.quit
        when 'g' then start_api_selection
        when 'd' then generate_documentation
        when 'r' then prompt_remove_api_and_docs
        when 'k'
          @active_pane.api_list? ? @api_list.up : @menu_list.up
          @window.update
        when 'j'
          @active_pane.api_list? ? @api_list.down : @menu_list.down
          @window.update
        else
          handle_secondary_key_press(char)
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

      # Starts selection mode in the API catalog list
      def start_api_selection
        @active_pane = FocusPane::ApiList
        @api_list.focus
        update_focus_ui
        @log_view.info "API Selection Mode: Use Up/Down arrow keys to highlight an API to install, then press Enter."
        @log_view.info "Tip: Press Escape or Left Arrow to return to the Main Menu."
        @window.update
      end

      # Returns focus to the Main Menu
      def return_to_menu
        @active_pane = FocusPane::Menu
        @menu_list.focus
        update_focus_ui
        @window.update
      end

      private def update_focus_ui
        if @active_pane.api_list?
          @menu_box.title = " Menu Options "
          @api_box.title = " Available Google APIs [Active - Enter to Install, Esc to Cancel] "
          @status_bar.content = " [↑/↓] Highlight API  [Enter] Install/Generate  [Esc/Tab/←] Back to Menu  [Q] Quit"
        else
          @menu_box.title = " Menu Options [Active] "
          @api_box.title = " Available Google APIs (Press [G] to Highlight) "
          @status_bar.content = " [↑/↓] Navigate  [Enter] Select  [G] Choose API  [D] Docs  [R] Remove API  [T] Test  [A] All  [C] Regen  [S] Sync  [Q] Quit"
        end
      end

      # Generates an API selected from the target list
      def generate_selected_api(index : Int32)
        target = @targets[index]?
        unless target
          @log_view.error "Invalid API target selected (index #{index})."
          return
        end
        perform_generation(target.id)
      end

      # Handles activation by index
      def execute_menu_action(index : Int32)
        if index < 4
          execute_primary_menu_action(index)
        else
          execute_secondary_menu_action(index)
        end
      end

      private def execute_primary_menu_action(index : Int32)
        case index
        when 0 then start_api_selection
        when 1 then generate_documentation
        when 2 then prompt_remove_api_and_docs
        when 3 then prompt_run_tests
        end
      end

      private def execute_secondary_menu_action(index : Int32)
        case index
        when 4 then run_all_unit_tests
        when 5 then clear_and_regenerate
        when 6 then sync_api_list_yaml
        when 7 then print_help
        when 8 then @window.quit
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
          refresh_targets_list
        else
          @log_view.error msg
          @status_bar.content = " Status: Generation failed for #{target_query}."
        end
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

      # Action 4: Remove API and documentation
      def prompt_remove_api_and_docs
        generated = Manager.find_generated_api_names(@project_root)
        if generated.empty?
          clean_docs_only
          return
        end

        highlighted = determine_highlighted_api
        prompt_label = if highlighted
                         "API to remove (default: #{highlighted}, or #{generated.join(", ")}, 'all', 'docs'):"
                       else
                         "API to remove (#{generated.join(", ")}, 'all', 'docs'):"
                       end

        CW::InputDialog.read(@window, prompt_label) do |input|
          target = (input && !input.strip.empty?) ? input.strip : highlighted
          if target
            perform_remove_api(target)
          else
            @log_view.info "Removal cancelled."
          end
          @menu_list.focus
          @window.update
        end
      end

      private def determine_highlighted_api : String?
        return unless @active_pane.api_list?
        target = @targets[@api_list.current_index]?
        (target && target.generated?) ? target.name : nil
      end

      private def clean_docs_only : Nil
        @log_view.warn "No generated APIs found to remove. Checking documentation..."
        success, msg = Manager.remove_docs(@project_root)
        if success
          @log_view.info msg
          @status_bar.content = " Status: Documentation cleaned up."
        else
          @log_view.error msg
          @status_bar.content = " Status: Documentation cleanup failed."
        end
        @window.update
      end

      private def perform_remove_api(api_query : String)
        @log_view.warn "Removing API and documentation matching '#{api_query}'..."
        @status_bar.content = " Status: Removing #{api_query}..."
        @window.update

        success, msg = Manager.remove_api(api_query, @project_root)
        if success
          @log_view.info msg
          @status_bar.content = " Status: Successfully removed #{api_query}!"
          refresh_targets_list
        else
          @log_view.error msg
          @status_bar.content = " Status: Removal failed for #{api_query}."
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
          @menu_list.focus
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
          refresh_targets_list
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
