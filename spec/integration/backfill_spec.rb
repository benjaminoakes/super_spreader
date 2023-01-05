# frozen_string_literal: true

require "active_job"
require "spec_helper"
require "support/log_spec_helper"

RSpec.describe "Integration" do
  include LogSpecHelper

  before do
    ExampleBackfillModel.reset!
  end

  it "can backfill using an example job" do
    1_000.times { ExampleBackfillModel.create }

    config = SuperSpreader::SchedulerConfig.new

    config.batch_size = 10
    config.duration = 10
    config.job_class_name = "ExampleBackfillJob"

    config.per_second_on_peak = 3.0
    config.per_second_off_peak = 7.5

    config.on_peak_timezone = "America/Los_Angeles"
    config.on_peak_wday_begin = 1
    config.on_peak_wday_end = 5
    config.on_peak_hour_begin = 5
    config.on_peak_hour_end = 17

    config.save

    expect(SuperSpreader::SchedulerConfig.new.serializable_hash).
      to eq({
        "batch_size" => 10,
        "duration" => 10,
        "job_class_name" => "ExampleBackfillJob",
        "on_peak_hour_begin" => 5,
        "on_peak_hour_end" => 17,
        "on_peak_timezone" => "America/Los_Angeles",
        "on_peak_wday_begin" => 1,
        "on_peak_wday_end" => 5,
        "per_second_off_peak" => 7.5,
        "per_second_on_peak" => 3.0
      })

    log = capture_log do
      perform_enqueued_jobs do
        SuperSpreader::SchedulerJob.perform_now
      end
    end

    # NOTE: There might be some extra runs of `SchedulerJob` at the end of the
    # log, but it's unclear whether that's because of `perform_enqueued_jobs`.
    # In any case, it's benign.
    expect(log.lines.length).to eq(15)
    example_backfill_models = ExampleBackfillModel.where(id: 1..1000)
    expect(example_backfill_models.length).to eq(1000)
    expect(example_backfill_models.all? { |m| m.example_attribute.present? }).to eq(true)
  end

  it "can backfill using a manually-set initial_id" do
    1_000.times { ExampleBackfillModel.create }

    config = SuperSpreader::SchedulerConfig.new

    config.batch_size = 10
    config.duration = 10
    config.job_class_name = "ExampleBackfillJob"

    config.per_second_on_peak = 3.0
    config.per_second_off_peak = 7.5

    config.on_peak_timezone = "America/Los_Angeles"
    config.on_peak_wday_begin = 1
    config.on_peak_wday_end = 5
    config.on_peak_hour_begin = 5
    config.on_peak_hour_end = 17

    config.save

    expect(SuperSpreader::SchedulerConfig.new.serializable_hash).
      to eq({
        "batch_size" => 10,
        "duration" => 10,
        "job_class_name" => "ExampleBackfillJob",
        "on_peak_hour_begin" => 5,
        "on_peak_hour_end" => 17,
        "on_peak_timezone" => "America/Los_Angeles",
        "on_peak_wday_begin" => 1,
        "on_peak_wday_end" => 5,
        "per_second_off_peak" => 7.5,
        "per_second_on_peak" => 3.0
      })

    tracker = SuperSpreader::SpreadTracker.new(ExampleBackfillJob, ExampleBackfillModel)
    tracker.initial_id = 500

    log = capture_log do
      perform_enqueued_jobs do
        SuperSpreader::SchedulerJob.perform_now
      end
    end

    processed_models = ExampleBackfillModel.where(id: 1..500)
    expect(processed_models.length).to eq(500)
    expect(processed_models.all? { |m| m.example_attribute.present? }).to eq(true)
    unprocessed_models = ExampleBackfillModel.where(id: 501..1000)
    expect(unprocessed_models.length).to eq(500)
    expect(unprocessed_models.all? { |m| m.example_attribute.present? }).to eq(false)
  end

  class ExampleBackfillModel
    @@records = {}

    attr_reader :id
    attr_accessor :example_attribute

    def initialize
      @id = self.class.maximum + 1
    end

    def save
      @@records[self.id] = self

      true
    end

    def self.reset!
      @@records = {}
    end

    def self.maximum(*)
      @@records.length
    end

    def self.create(...)
      instance = new(...)
      instance.save
      instance
    end

    def self.where(id:)
      id_range = id

      @@records.
        select { |id, _instance| id_range.cover?(id) }.
        values
    end
  end

  class ExampleBackfillJob < ActiveJob::Base
    extend SuperSpreader::StopSignal

    def self.model_class
      ExampleBackfillModel
    end

    def perform(begin_id, end_id)
      return if self.class.stopped?

      # In a real application, this section would make use of the appropriate,
      # efficient database queries.

      ExampleBackfillModel.where(id: begin_id..end_id).each do |example_backfill_model|
        example_backfill_model.example_attribute = "example value"
      end
    end
  end

  describe ExampleBackfillJob do
    it "has SuperSpreader support" do
      expect(described_class.model_class).to eq(ExampleBackfillModel)
    end

    it "sets values on in-memory instances" do
      example_backfill_model_1 = ExampleBackfillModel.create
      example_backfill_model_2 = ExampleBackfillModel.create

      described_class.perform_now(example_backfill_model_1.id, example_backfill_model_2.id)

      expect(example_backfill_model_1.example_attribute).to be_present
      expect(example_backfill_model_1.example_attribute).to be_present
    end

    it "can be stopped" do
      example_backfill_model_1 = ExampleBackfillModel.create
      example_backfill_model_2 = ExampleBackfillModel.create

      described_class.stop!
      described_class.perform_now(example_backfill_model_1.id, example_backfill_model_2.id)

      expect(described_class).to be_stopped
      expect(example_backfill_model_1.example_attribute).not_to be_present
      expect(example_backfill_model_1.example_attribute).not_to be_present
    end
  end
end