# frozen_string_literal: true

require "spec_helper"

RSpec.describe SuperSpreader::MigrationHelper do
  it "can backfill using an example migration" do
    example_backfill_migration = Class.new(ActiveRecord::Migration[6.1]) do
      include SuperSpreader::MigrationHelper

      # See https://github.com/ankane/strong_migrations#backfilling-data
      disable_ddl_transaction!

      def up
        batch_execute(table_name: "example_models", step_size: 100) do |min, max|
          <<~SQL
            UPDATE example_models
            SET example_attribute = "example"
            WHERE example_attribute IS NULL
              AND id >= #{min}
              AND id < #{max}
            ;
          SQL
        end
      end

      def down
        batch_execute(table_name: "example_models", step_size: 100) do |min, max|
          <<~SQL
            UPDATE example_models
            SET example_attribute = NULL
            WHERE example_attribute IS NOT NULL
              AND id >= #{min}
              AND id < #{max}
            ;
          SQL
        end
      end
    end

    create_list(:example_model, 1000)

    ActiveRecord::Migration.suppress_messages do
      example_backfill_migration.migrate(:up)
      expect(ExampleModel.where(example_attribute: nil).count).to eq(0)
      expect(ExampleModel.where.not(example_attribute: nil).count).to eq(1000)

      example_backfill_migration.migrate(:down)
      expect(ExampleModel.where(example_attribute: nil).count).to eq(1000)
      expect(ExampleModel.where.not(example_attribute: nil).count).to eq(0)
    end
  end
end
