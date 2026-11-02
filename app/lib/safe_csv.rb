# frozen_string_literal: true

require "csv"

# CSV.generate_line for files people open in a spreadsheet. Excel, Sheets and LibreOffice run a
# cell that starts with =, +, - or @ as a formula, and OWASP adds a leading tab or carriage return
# to that list. CSV quoting doesn't help, because the app strips the quotes before it looks. So a
# member who names themselves =HYPERLINK("http://evil","x") plants a live link in whoever opens
# the export. Prefixing a single quote makes the cell read as text. Use this for any CSV row with
# user-controlled values in it.
module SafeCsv
  # OWASP's list, plus whitespace before a trigger, in case an importer trims it off first.
  FORMULA_START = /\A(?:[\t\r]|\s*[=+\-@])/

  class << self
    def generate_line(row, **options)
      CSV.generate_line(row.map { |cell| escape(cell) }, **options)
    end

    # Only the start of the cell counts, so "Mary-Jane" and "jane+tag@example.com" pass through
    # untouched. Numbers can't carry a formula, and a negative one should stay a number.
    def escape(cell)
      return cell if cell.nil? || cell.is_a?(Numeric)

      text = cell.to_s
      text.match?(FORMULA_START) ? "'#{text}" : cell
    end
  end
end
