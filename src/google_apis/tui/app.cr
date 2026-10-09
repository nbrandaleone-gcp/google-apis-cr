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
        LogView
      end

      getter window : CT::Window
      getter project_root : String
      getter menu_box : CW::GroupBox
      getter menu_list : CW::List
      getter api_box : CW::GroupBox
      getter search_bar : CW::Box
      getter api_list : CW::List
      getter output_box : CW::GroupBox
      getter log_view : CW::Log
      getter status_bar : CW::Box
      property active_pane : FocusPane = FocusPane::Menu
      getter targets : Array(DiscoveryTarget)
      getter filtered_targets : Array(DiscoveryTarget)
      property search_query : String = ""

      MENU_ITEMS = [
        "[G] Generate API (Choose Target)",
        "[F] Filter / Search APIs",
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
        @window.tab_navigation = false
        @targets = [] of DiscoveryTarget
        @filtered_targets = [] of DiscoveryTarget

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

        # Menu Panel (Left side) - Blue border
        @menu_box = CW::GroupBox.new(
          parent: @window,
          top: 3,
          left: 0,
          width: 44,
          bottom: 2,
          title: " Menu Options [Active] ",
          style: CT::Style.new(border: CT::Border.new(type: CT::BorderType::Solid, fg: "blue"))
        )
        @menu_box.stylesheet = "GroupBox { border: solid; border-color: blue; }"

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

        # API Targets Panel (Right side, upper half above log output) - Green border
        @api_box = CW::GroupBox.new(
          parent: @window,
          top: 3,
          left: 44,
          right: 0,
          height: "48%",
          title: " Available Google APIs (Press [G] to Highlight) ",
          style: CT::Style.new(border: CT::Border.new(type: CT::BorderType::Solid, fg: "green"))
        )
        @api_box.stylesheet = "GroupBox { border: solid; border-color: green; }"

        # Search Bar widget inside API box (top line)
        @search_bar = CW::Box.new(
          parent: @api_box,
          top: 1,
          left: 1,
          right: 1,
          height: 1,
          parse_tags: true,
          content: ""
        )

        # API List widget inside API box (below search bar)
        @api_list = CW::List.new(
          parent: @api_box,
          top: 2,
          left: 1,
          right: 1,
          bottom: 1,
          items: [] of String,
          mouse: true,
          vi_keys: true,
          styles: CT::Styles.new(
            selected: CT::Style.new(bg: "green", fg: "white", bold: true),
          )
        )

        # Output / Log Panel (Right side, lower half below API list) - Red border
        @output_box = CW::GroupBox.new(
          parent: @window,
          top: "48%+3",
          left: 44,
          right: 0,
          bottom: 2,
          title: " Activity Log & Output ",
          style: CT::Style.new(border: CT::Border.new(type: CT::BorderType::Solid, fg: "red"))
        )
        @output_box.stylesheet = "GroupBox { border: solid; border-color: red; }"

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
          content: " [↑/↓] Navigate  [Enter] Select  [Tab] Switch Widget  [F] Search  [PgUp/PgDn] Page  [D] Docs  [R] Remove  [Q] Quit"
        )

        load_targets
        wire_events
        log_welcome
        @menu_list.focus
      end

      private def load_targets
        @targets = Manager.list_targets(allow_network: false, project_root: @project_root)
        if @targets.empty?
          @targets = Manager.list_targets(allow_network: true, project_root: @project_root)
        end
        @targets.sort_by! { |target| {target.generated? ? 0 : 1, target.id} }
        apply_search_filter(@search_query)
      end

      # Updates the search bar text reflecting active query & match count
      private def update_search_bar_ui
        if @search_query.empty?
          @search_bar.content = " {bold}Filter:{/bold} {#64748b-fg}[None - All #{@targets.size} APIs]{/#64748b-fg}  {dim}Press [F] to Search  [PgUp/PgDn] Page Screen  [C] Clear{/dim}"
        elsif @filtered_targets.empty?
          @search_bar.content = " {bold}Filter:{/bold} {#ff5555-fg}'#{@search_query}' (0 / #{@targets.size} matched){/#ff5555-fg}  {dim}Press [F] to Search  [C] to Clear{/dim}"
        else
          @search_bar.content = " {bold}Filter:{/bold} {#57c7ff-fg}'#{@search_query}'{/#57c7ff-fg} ({#a7f3d0-fg}#{@filtered_targets.size} / #{@targets.size} matched{/#a7f3d0-fg})  {dim}[F] Change  [C] Clear  [PgUp/PgDn] Page{/dim}"
        end
      end

      # Filters targets by query substring matching ID, name, version, or title
      def apply_search_filter(query : String)
        @search_query = query.strip
        if @search_query.empty?
          @filtered_targets = @targets.dup
        else
          q = @search_query.downcase
          @filtered_targets = @targets.select do |target|
            target.id.downcase.includes?(q) ||
              target.name.downcase.includes?(q) ||
              target.title.downcase.includes?(q) ||
              target.version.downcase.includes?(q)
          end
        end

        @api_list.items = @filtered_targets.map { |target| target_item_label(target) }
        @api_list.current_index = 0 unless @filtered_targets.empty?
        update_search_bar_ui
        update_focus_ui
      end

      # Clears active search filter and restores all targets
      def clear_search_filter
        apply_search_filter("")
        @log_view.info "Search filter cleared. Showing all #{@targets.size} Google APIs."
        @window.update
      end

      # Opens an interactive input dialog to search/filter the API catalog
      def prompt_search_api
        CW::InputDialog.read(@window, "Search APIs (by name, ID, or title):", @search_query) do |input|
          if input
            apply_search_filter(input)
            if @filtered_targets.empty?
              @log_view.warn "No Google APIs found matching '#{input}'. Press [C] to clear filter."
            else
              @log_view.info "Filter applied: #{@filtered_targets.size} of #{@targets.size} APIs match '#{input}'."
            end
          else
            @log_view.info "Search cancelled."
          end
          switch_pane(FocusPane::ApiList)
        end
      end

      # Computes the number of items to skip for full page up / down
      private def page_step : Int32
        vis = @api_list.aheight - 2
        vis > 2 ? vis : 10
      end

      private def target_item_label(target : DiscoveryTarget) : String
        status = target.generated? ? "[INSTALLED]" : "[AVAILABLE]"
        "#{status.ljust(12)} #{target.id.ljust(22)} #{target.title}"
      end

      # Refreshes catalog and redisplays labels (e.g. after install or remove)
      def refresh_targets_list
        load_targets
        @api_list.items = @filtered_targets.map { |target| target_item_label(target) }
        update_search_bar_ui
        update_focus_ui
        @window.update
      end

      private def log_welcome
        @log_view.info "Welcome to Google APIs Crystal Generator TUI!"
        @log_view.info "Use Up/Down arrows to navigate, [Tab] to switch between active window widgets."
        @log_view.info "Press [G] to choose and install an API from the catalog list above."
        @log_view.info "Shortcuts: [G] Choose API, [F] Search/Filter, [Tab] Next Widget, [D] Docs, [R] Remove, [Q] Quit"

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
          if !@search_query.empty?
            clear_search_filter
          else
            return_to_menu
          end
        end

        # Focus synchronization across all panes
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

        @log_view.on(CT::Event::FocusIn) do |_e|
          @active_pane = FocusPane::LogView
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

        # Allow <Tab> and <Shift+Tab> to switch active window widgets
        if e.key == ::Tput::Key::Tab || e.char == '\t'
          e.accept
          cycle_focus(forward: true)
          return
        elsif e.key == ::Tput::Key::ShiftTab
          e.accept
          cycle_focus(forward: false)
          return
        end

        return if handle_navigation_keys(e)
        return if handle_action_keys(e)
        return if e.accepted?

        char = e.char
        return unless char
        handle_char_keys(char.downcase)
      end

      # Cycles focus among Menu, ApiList, and LogView
      def cycle_focus(forward : Bool = true)
        next_pane = if forward
                      case @active_pane
                      in FocusPane::Menu    then FocusPane::ApiList
                      in FocusPane::ApiList then FocusPane::LogView
                      in FocusPane::LogView then FocusPane::Menu
                      end
                    else
                      case @active_pane
                      in FocusPane::Menu    then FocusPane::LogView
                      in FocusPane::ApiList then FocusPane::Menu
                      in FocusPane::LogView then FocusPane::ApiList
                      end
                    end
        switch_pane(next_pane)
      end

      # Sets active pane and focuses its corresponding widget
      def switch_pane(pane : FocusPane)
        @active_pane = pane
        case pane
        when FocusPane::Menu
          @menu_list.focus
        when FocusPane::ApiList
          @api_list.focus
        when FocusPane::LogView
          @log_view.focus
        end
        update_focus_ui
        @window.update
      end

      # Handles directional and screen-jumping navigation keys
      private def handle_navigation_keys(e : CT::Event::KeyPress) : Bool
        handle_arrow_keys(e) || handle_page_keys(e) || handle_edge_keys(e)
      end

      private def handle_arrow_keys(e : CT::Event::KeyPress) : Bool
        case e.key
        when ::Tput::Key::Up
          unless e.accepted?
            case @active_pane
            when .api_list? then @api_list.up
            when .log_view? then @log_view.scroll -1
            else                 @menu_list.up
            end
            @window.update
          end
          true
        when ::Tput::Key::Down
          unless e.accepted?
            case @active_pane
            when .api_list? then @api_list.down
            when .log_view? then @log_view.scroll 1
            else                 @menu_list.down
            end
            @window.update
          end
          true
        else
          false
        end
      end

      private def handle_page_keys(e : CT::Event::KeyPress) : Bool
        step = page_step
        case e.key
        when ::Tput::Key::PageDown, ::Tput::Key::CtrlF, ::Tput::Key::CtrlD
          unless e.accepted?
            case @active_pane
            when .api_list? then @api_list.down(step)
            when .log_view? then @log_view.scroll step
            else                 @menu_list.down(step)
            end
            @window.update
          end
          true
        when ::Tput::Key::PageUp, ::Tput::Key::CtrlB, ::Tput::Key::CtrlU
          unless e.accepted?
            case @active_pane
            when .api_list? then @api_list.up(step)
            when .log_view? then @log_view.scroll -step
            else                 @menu_list.up(step)
            end
            @window.update
          end
          true
        else
          false
        end
      end

      private def handle_edge_keys(e : CT::Event::KeyPress) : Bool
        case e.key
        when ::Tput::Key::Home
          unless e.accepted?
            case @active_pane
            when .api_list? then @api_list.current_index = 0 unless @filtered_targets.empty?
            when .log_view? then @log_view.scroll_to 0
            else                 @menu_list.current_index = 0
            end
            @window.update
          end
          true
        when ::Tput::Key::End
          unless e.accepted?
            case @active_pane
            when .api_list? then @api_list.current_index = @filtered_targets.size - 1 unless @filtered_targets.empty?
            when .log_view? then @log_view.scroll_to 99999
            else                 @menu_list.current_index = MENU_ITEMS.size - 1
            end
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
            elsif @active_pane.menu?
              execute_menu_action(@menu_list.current_index)
            end
          end
          true
        when ::Tput::Key::Escape, ::Tput::Key::Left
          return false if @active_pane.menu?
          if @active_pane.api_list? && !@search_query.empty?
            clear_search_filter
          else
            return_to_menu
          end
          true
        when ::Tput::Key::Right
          return false unless @active_pane.menu?
          start_api_selection
          true
        else
          false
        end
      end

      private def handle_char_keys(char : Char)
        case @active_pane
        when .api_list? then handle_api_list_char_keys(char)
        when .log_view? then handle_log_view_char_keys(char)
        else                 handle_menu_char_keys(char)
        end
      end

      private def handle_api_list_char_keys(char : Char)
        case char
        when 'f'
          prompt_search_api
        when 'c'
          clear_search_filter
        when ' ', ']'
          @api_list.down(page_step)
          @window.update
        when '['
          @api_list.up(page_step)
          @window.update
        when 'k'
          @api_list.up
          @window.update
        when 'j'
          @api_list.down
          @window.update
        when 'q'
          @window.quit
        else
          handle_shared_char_keys(char)
        end
      end

      private def handle_log_view_char_keys(char : Char)
        case char
        when 'k'
          @log_view.scroll -1
          @window.update
        when 'j'
          @log_view.scroll 1
          @window.update
        when ' ', ']'
          @log_view.scroll page_step
          @window.update
        when '['
          @log_view.scroll -page_step
          @window.update
        when 'q'
          @window.quit
        else
          handle_shared_char_keys(char)
        end
      end

      private def handle_menu_char_keys(char : Char)
        case char
        when 'q' then @window.quit
        when 'g' then start_api_selection
        when 'f' then prompt_search_api
        when 'd' then generate_documentation
        when 'r' then prompt_remove_api_and_docs
        when 'k'
          @menu_list.up
          @window.update
        when 'j'
          @menu_list.down
          @window.update
        else
          handle_shared_char_keys(char)
        end
      end

      private def handle_shared_char_keys(char : Char)
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
        switch_pane(FocusPane::ApiList)
        @log_view.info "API Chooser Active (#{@filtered_targets.size} APIs). Use [PgUp]/[PgDn] to skip screenfuls, [F] to search/filter."
        @log_view.info "Tip: Press [Enter] to install selected API, [C] to clear filter, [Tab] to switch widget, [Esc] for Menu."
      end

      # Returns focus to the Main Menu
      def return_to_menu
        switch_pane(FocusPane::Menu)
      end

      private def update_focus_ui
        filter_label = @search_query.empty? ? "" : " [Filter: '#{@search_query}' - #{@filtered_targets.size} matched]"
        case @active_pane
        when .menu?
          @menu_box.title = " Menu Options [Active] "
          @api_box.title = " Available Google APIs#{filter_label} "
          @output_box.title = " Activity Log & Output "
          @status_bar.content = " [↑/↓] Navigate  [Enter] Select  [Tab] Switch Widget  [F] Search  [D] Docs  [R] Remove  [Q] Quit"
        when .api_list?
          @menu_box.title = " Menu Options "
          @api_box.title = " Available Google APIs#{filter_label} [Active - Enter to Install, Esc for Menu] "
          @output_box.title = " Activity Log & Output "
          @status_bar.content = " [↑/↓] Move  [PgUp/PgDn] Page Screen  [Tab] Switch Widget  [F] Search  [C] Clear  [Enter] Install  [Esc] Menu"
        when .log_view?
          @menu_box.title = " Menu Options "
          @api_box.title = " Available Google APIs#{filter_label} "
          @output_box.title = " Activity Log & Output [Active - ↑/↓/PgUp/PgDn to Scroll] "
          @status_bar.content = " [↑/↓] Scroll Log  [PgUp/PgDn] Page Scroll  [Tab] Switch Widget  [Esc] Menu  [Q] Quit"
        end
      end

      # Generates an API selected from the filtered target list
      def generate_selected_api(index : Int32)
        target = @filtered_targets[index]?
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
        when 1 then prompt_search_api
        when 2 then generate_documentation
        when 3 then prompt_remove_api_and_docs
        end
      end

      private def execute_secondary_menu_action(index : Int32)
        case index
        when 4 then prompt_run_tests
        when 5 then run_all_unit_tests
        when 6 then clear_and_regenerate
        when 7 then sync_api_list_yaml
        when 8 then print_help
        when 9 then @window.quit
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

      # Generate documentation using `crystal docs`
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

      # Remove API and documentation
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
          switch_pane(FocusPane::Menu)
        end
      end

      private def determine_highlighted_api : String?
        target = @filtered_targets[@api_list.current_index]?
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
          Manager.sync_api_list_yaml(@project_root)
        else
          @log_view.error msg
          @status_bar.content = " Status: Removal failed for #{api_query}."
        end
        @window.update
      end

      # Run unit tests for particular API
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
          switch_pane(FocusPane::Menu)
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

      # Run all tests
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

      # Clear out existing generated APIs and regenerate them
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
          refresh_targets_list
        end
        @window.update
      end

      # Sync Discovery Docs versions to api-list.yaml
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

      # Print help
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
