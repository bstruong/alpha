# frozen_string_literal: true

require "json"
require_relative "ollama_client"
require_relative "scorer"

# Orchestrates the benchmark: for each model, runs every fixture N times,
# scores each result, and aggregates into a per-model summary. Prints a
# comparison table at the end.
#
# Collaborators are injected (Sandi) — tests pass fakes for the client and
# scorer; no network or mocking framework needed.
class BenchmarkRunner
  EXTRACTION_PROMPT = <<~PROMPT
    You are a financial statement extractor. Given the raw text of a bank
    or brokerage statement, extract the structured data as JSON matching
    the provided schema. Output ONLY valid JSON, no prose, no markdown.
    All money values are integer cents. Dates are YYYY-MM-DD. If a field
    is absent, use null.

    Statement text:
    %<source>s
  PROMPT

  # Ollama structured-output schema. Passed as the `format` parameter so we
  # test the same enforcement path ASSASSIN would use in production.
  SCHEMA = {
    type: "object",
    properties: {
      institution_slug: { type: "string" },
      account_number_last_four: { type: "string" },
      period_start: { type: "string" },
      period_end: { type: "string" },
      beginning_balance_cents: { type: "integer" },
      ending_balance_cents: { type: "integer" },
      transactions: {
        type: "array",
        items: {
          type: "object",
          properties: {
            posted_at: { type: "string" },
            description: { type: "string" },
            amount_cents: { type: "integer" },
            transaction_kind_hint: { type: "string" }
          },
          required: %w[posted_at description amount_cents transaction_kind_hint]
        }
      }
    },
    required: %w[
      institution_slug account_number_last_four period_start period_end
      beginning_balance_cents ending_balance_cents transactions
    ]
  }.freeze

  def initialize(fixtures_root:, runs: 3, client: OllamaClient.new, scorer: Scorer.new)
    @fixtures_root = fixtures_root
    @runs = runs
    @client = client
    @scorer = scorer
  end

  def run(models:)
    fixtures = load_fixtures
    raise "no fixtures found in #{@fixtures_root}" if fixtures.empty?

    summaries = models.map { |model| benchmark_model(model, fixtures) }
    print_report(summaries)
    summaries
  end

  private

  attr_reader :fixtures_root, :runs, :client, :scorer

  Fixture = Data.define(:name, :source_text, :expected)

  ModelSummary = Data.define(
    :model, :json_valid_rate, :field_accuracy, :money_exact_rate,
    :txn_precision, :txn_recall, :tokens_per_second
  )

  def load_fixtures
    Dir.children(fixtures_root).sort.filter_map do |name|
      dir = File.join(fixtures_root, name)
      next unless File.directory?(dir)

      Fixture.new(
        name: name,
        source_text: File.read(File.join(dir, "source.txt")),
        expected: JSON.parse(File.read(File.join(dir, "expected.json")))
      )
    end
  end

  def benchmark_model(model, fixtures)
    warn "Benchmarking #{model}..."
    results = fixtures.flat_map { |fixture| run_fixture(model, fixture) }
    aggregate(model, results)
  end

  # Returns an array of [Score, tokens_per_second] for the N runs.
  def run_fixture(model, fixture)
    Array.new(runs) do
      response = client.extract(
        model: model,
        prompt: format(EXTRACTION_PROMPT, source: fixture.source_text),
        schema: SCHEMA
      )
      score = scorer.score(expected: fixture.expected, actual: response.parsed)
      [score, response.tokens_per_second]
    end
  end

  def aggregate(model, results)
    scores = results.map(&:first)
    speeds = results.map(&:last)

    ModelSummary.new(
      model: model,
      json_valid_rate: rate(scores, &:json_valid),
      field_accuracy: mean(scores.map(&:field_accuracy)),
      money_exact_rate: rate(scores, &:money_exact),
      txn_precision: mean(scores.map(&:txn_precision)),
      txn_recall: mean(scores.map(&:txn_recall)),
      tokens_per_second: mean(speeds)
    )
  end

  def rate(scores, &predicate)
    return 0.0 if scores.empty?

    scores.count(&predicate).to_f / scores.size
  end

  def mean(values)
    return 0.0 if values.empty?

    (values.sum / values.size).round(3)
  end

  def print_report(summaries)
    puts "\n#{'=' * 78}"
    puts "BENCHMARK RESULTS (#{runs} runs per fixture)"
    puts "=" * 78
    header = format(
      "%-22s %8s %8s %8s %8s %8s %8s",
      "Model", "JSON%", "Field", "Money%", "Prec", "Recall", "Tok/s"
    )
    puts header
    puts "-" * 78
    summaries.each { |s| puts summary_row(s) }
    puts "=" * 78
    puts "\nWeighting (see README): accuracy+money 40%, JSON-validity 25%,"
    puts "speed 20%, VRAM fit 10%, setup 5%. Apply weights to pick a winner."
  end

  def summary_row(summary)
    format(
      "%-22s %7.0f%% %8.2f %7.0f%% %8.2f %8.2f %8.1f",
      summary.model,
      summary.json_valid_rate * 100,
      summary.field_accuracy,
      summary.money_exact_rate * 100,
      summary.txn_precision,
      summary.txn_recall,
      summary.tokens_per_second
    )
  end
end
