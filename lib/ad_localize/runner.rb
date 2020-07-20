module AdLocalize
  class Runner
    attr_accessor :options

    def initialize
      @options = OptionHandler.parse
    end

    def run(args = ARGV)
        LOGGER.log(:info, :green, "OPTIONS : #{options}")
        input_files = args
        drive_key = options.dig(:drive_key)
        has_drive_key = !drive_key.blank?

        missing_csv_file = input_files.length.zero? && !has_drive_key
        raise 'No CSV to parse. Use option -h to see how to use this script' if missing_csv_file

        files_to_parse = []
        drive_files = []

        if has_drive_key
            LOGGER.log(:warn, :yellow, 'CSV file are ignored with the drive key option') if args.length > 1
            drive_key = options.dig(:drive_key)
            should_exports_all_sheets = options.dig(:export_all_sheets)
            if should_exports_all_sheets
                drive_files = SpreadSheetManager.download_all_sheets_from_drive(drive_key)
                files_to_parse += drive_files
            else
                drive_file = SpreadSheetManager.download_from_drive(
                    drive_key,
                    options.dig(:sheet_id),
                    options.dig(:use_service_account)
                )
                drive_files.push(drive_file)
                files_to_parse.push(drive_file)
            end
        else
            files_to_parse += input_files
        end

        LOGGER.log(:debug, :black, "FILES: #{files_to_parse}")
        if files_to_parse.length > 1
            export_all(files_to_parse, merge_policy: options.dig(:merge))
        else
            export(files_to_parse.first)
        end
        drive_files.each { |file| SpreadSheetManager.delete_drive_file(file) }
    end

    private

    def export_all(files, merge_policy: nil)
        csv_files = CsvFileManager.select_csvs(files)
        if merge_policy.nil?
            csv_files.each do |file|
                export(file, File.basename(file, '.csv'))
            end
        else
            merge_and_export_csvs(csv_files, merge_policy)
        end
    end

    def merge_and_export_csvs(files, merge_policy)
        LOGGER.log(:info, :green, "********* MERGING (#{merge_policy}) *********")
        LOGGER.log(:info, :green, 'Merging data from files...')
        output_file = files.first
        parser = CsvParser.new

        data_set = files.map { |file| parser.extract_data(file) }
        replace_previous = merge_policy == AdLocalize::Constant::REPLACE_MERGE_POLICY
        data = data_set.reduce(data_set.first) do |result, data|
            result.deep_merge!(data) do |_, previous, current|
                replace_previous ? current : previous
            end
        end
        export_data(parser, data)
    end

    def export(file, output_path_suffix = "")
      LOGGER.log(:info, :green, "********* PARSING #{file} *********")
      LOGGER.log(:info, :green, "Extracting data from file...")
      parser = CsvParser.new
      data = parser.extract_data(file)
      export_data(parser, data, output_path_suffix)
    end

    def export_data(parser, data, output_path_suffix = "")
        if data.empty?
          LOGGER.log(:error, :red, "No data were found in the file - check if there is a key column in the file")
        else
          export_platforms = options.dig(:only) || Constant::SUPPORTED_PLATFORMS
          add_intermediate_platform_dir = export_platforms.length > 1
          output_path = option_output_path_or_default
          export_platforms.each do |platform|
            platform_formatter = "AdLocalize::Platform::#{platform.to_s.camelize}Formatter".constantize.new(
              parser.locales.first,
              output_path + '/' + output_path_suffix,
              add_intermediate_platform_dir
            )
            parser.locales.each do |locale|
              platform_formatter.export(locale, data)
            end
          end
        end
    end

    def option_output_path_or_default
        options.dig(:output_path).presence || AdLocalize::Constant::EXPORT_FOLDER
    end
  end
end
