# frozen_string_literal: true

require "spec_helper"

# rubocop:disable RSpec/NestedGroups
describe PgSearch::Multisearchable do
  with_table "pg_search_documents", &DOCUMENTS_SCHEMA

  describe "a model that is multisearchable" do
    with_model :ModelThatIsMultisearchable do
      table do |t|
        t.string :some_content
      end

      model do
        include PgSearch::Model
        multisearchable against: :some_content
      end
    end

    with_model :MultisearchableParent do
      table do |t|
        t.string :secret
      end

      model do
        include PgSearch::Model
        multisearchable against: :secret

        has_many :multisearchable_children, dependent: :destroy
      end
    end

    with_model :MultisearchableChild do
      table do |t|
        t.belongs_to :multisearchable_parent, index: false
      end

      model do
        belongs_to :multisearchable_parent

        after_destroy do
          multisearchable_parent.update_attribute(:secret, rand(1000).to_s) # rubocop:disable Rails/SkipsModelValidations
        end
      end
    end

    describe "callbacks" do
      describe "after_create" do
        let(:record) { ModelThatIsMultisearchable.new(some_content: 'random') }

        describe "saving the record" do
          it "creates a PgSearch::Document record" do
            expect { record.save! }.to change(PgSearch::Document, :count).by(1)
          end

          context "with multisearch disabled" do
            before { allow(PgSearch).to receive(:multisearch_enabled?).and_return(false) }

            it "does not create a PgSearch::Document record" do
              expect { record.save! }.not_to change(PgSearch::Document, :count)
            end
          end
        end

        describe "the document" do
          it "is associated to the record" do
            record.save!
            newest_pg_search_document = PgSearch::Document.last
            expect(record.pg_search_documents.last).to eq(newest_pg_search_document)
            expect(newest_pg_search_document.searchable).to eq(record)
          end
        end
      end

      describe "after_update" do
        let!(:record) { ModelThatIsMultisearchable.create!(some_content: 'random') }

        context "when the document is present" do
          before { expect(record.pg_search_documents).to be_present }

          describe "saving the record" do
            it "calls save on the pg_search_documents" do
              expect { record.update some_content: 'changed' }.to(change { record.pg_search_documents.reload.first.content })
            end

            it "does not create a PgSearch::Document record" do
              expect { record.update some_content: 'changed' }.not_to change(PgSearch::Document, :count)
            end

            context "with multisearch disabled" do
              before { allow(PgSearch).to receive(:multisearch_enabled?).and_return(false) }

              it "does not create a PgSearch::Document record" do
                expect { record.update some_content: 'changed' }.not_to(change { record.pg_search_documents.reload.first.content })
              end
            end
          end
        end

        context "when the document is missing" do
          before { record.pg_search_documents.destroy_all }

          describe "saving the record" do
            it "creates a PgSearch::Document record" do
              expect { record.save! }.to change(PgSearch::Document, :count).by(1)
            end

            context "with multisearch disabled" do
              before { allow(PgSearch).to receive(:multisearch_enabled?).and_return(false) }

              it "does not create a PgSearch::Document record" do
                expect { record.save! }.not_to change(PgSearch::Document, :count)
              end
            end
          end
        end
      end

      describe "after_destroy" do
        it "removes its documents" do
          record = ModelThatIsMultisearchable.create!(some_content: 'random')
          document_ids = record.pg_search_document_ids
          expect { record.destroy }.to change(PgSearch::Document, :count).by(-1)
          expect { PgSearch::Document.find(document_ids) }.to raise_error(ActiveRecord::RecordNotFound)
        end

        it "removes its document in case of complex associations", :ignore do
          parent = MultisearchableParent.create!(secret: rand(1000).to_s)

          MultisearchableChild.create!(multisearchable_parent: parent)
          MultisearchableChild.create!(multisearchable_parent: parent)

          document_ids = parent.pg_search_document_ids

          expect { parent.destroy }.to change(PgSearch::Document, :count).by(-1)
          expect { PgSearch::Document.find(document_ids) }.to raise_error(ActiveRecord::RecordNotFound)
        end
      end
    end

    describe "populating the searchable text" do
      subject { record }

      let(:record) { ModelThatIsMultisearchable.new }

      before do
        ModelThatIsMultisearchable.multisearchable(multisearchable_options)
      end

      context "when searching against a single column" do
        let(:multisearchable_options) { { against: :some_content } }
        let(:text) { "foo bar" }

        before do
          without_partial_double_verification do
            allow(record).to receive(:some_content) { text }
          end
          record.save
        end

        describe '#content' do
          subject { super().pg_search_documents.first.content }

          it { is_expected.to eq(text) }
        end
      end

      context "when searching against multiple columns" do
        let(:multisearchable_options) { { against: %i[attr_1 attr_2] } }

        before do
          without_partial_double_verification do
            allow(record).to receive(:attr_1).and_return('1')
            allow(record).to receive(:attr_2).and_return('2')
          end
          record.save
        end

        describe '#content' do
          subject { super().pg_search_documents.first.content }

          it { is_expected.to eq("1 2") }
        end
      end
    end

    describe "populating the searchable attributes" do
      subject { record }

      let(:record) { ModelThatIsMultisearchable.new some_content: 'random' }

      before do
        ModelThatIsMultisearchable.multisearchable(multisearchable_options)
      end

      context "when searching against a single column" do
        let(:multisearchable_options) { { against: :some_content } }
        let(:text) { "foo bar" }

        before do
          without_partial_double_verification do
            allow(record).to receive(:some_content) { text }
          end
          record.save
        end

        describe '#content' do
          subject { super().pg_search_documents.first.content }

          it { is_expected.to eq(text) }
        end
      end

      context "when searching against multiple columns" do
        let(:multisearchable_options) { { against: %i[attr_1 attr_2] } }

        before do
          without_partial_double_verification do
            allow(record).to receive(:attr_1).and_return('1')
            allow(record).to receive(:attr_2).and_return('2')
          end
          record.save
        end

        describe '#content' do
          subject { super().pg_search_documents.first.content }

          it { is_expected.to eq("1 2") }
        end
      end

      context "with additional_attributes" do
        let(:multisearchable_options) do
          {
            against: :some_content,
            additional_attributes: lambda do |record|
              { additional_attribute_column: record.bar }
            end
          }
        end
        let(:text) { "foo bar" }

        it "sets the attributes" do
          without_partial_double_verification do
            allow(record).to receive(:bar).and_return(text)
            allow(record).to receive(:create_pg_search_document)
            record.save
            expect(record.reload.pg_search_documents.first.additional_attribute_column).to eq(text)
          end
        end
      end

      context "when selectively updating" do
        let(:multisearchable_options) do
          {
            against: :some_content,
            update_if: lambda do |record|
              record.bar?
            end
          }
        end
        let(:text) { "foo bar" }

        it "creates the document" do
          without_partial_double_verification do
            allow(record).to receive(:bar?).and_return(false)
            allow(record).to receive(:create_pg_search_document)
            record.save
            expect(record.reload.pg_search_documents.first.content).to eq(record.some_content)
          end
        end

        context "when the document is created" do
          before { record.save }

          context "when update_if returns false" do
            before do
              without_partial_double_verification do
                allow(record).to receive(:bar?).and_return(false)
              end
            end

            it "does not update the document" do
              without_partial_double_verification do
                expect { record.update some_content: 'changed' }.not_to(change { record.pg_search_documents.reload.first.content })
              end
            end
          end

          context "when update_if returns true" do
            before do
              without_partial_double_verification do
                allow(record).to receive(:bar?).and_return(true)
              end
            end

            it "updates the document" do
              expect { record.update some_content: 'changed' }.to(change { record.pg_search_documents.reload.first.content })
            end
          end
        end
      end
    end
  end

  describe "a model which is conditionally multisearchable using a Proc" do
    context "via :if" do
      with_model :ModelThatIsMultisearchable do
        table do |t|
          t.string :some_content
          t.boolean :multisearchable
        end

        model do
          include PgSearch::Model
          multisearchable against: :some_content, if: ->(record) { record.multisearchable? }
        end
      end

      describe "callbacks" do
        describe "after_create" do
          describe "saving the record" do
            context "when the condition is true" do
              let(:record) { ModelThatIsMultisearchable.new(some_content: 'random', multisearchable: true) }

              it "creates a PgSearch::Document record" do
                expect { record.save! }.to change(PgSearch::Document, :count).by(1)
              end

              context "with multisearch disabled" do
                before { allow(PgSearch).to receive(:multisearch_enabled?).and_return(false) }

                it "does not create a PgSearch::Document record" do
                  expect { record.save! }.not_to change(PgSearch::Document, :count)
                end
              end
            end

            context "when the condition is false" do
              let(:record) { ModelThatIsMultisearchable.new(some_content: 'random', multisearchable: false) }

              it "does not create a PgSearch::Document record" do
                expect { record.save! }.not_to change(PgSearch::Document, :count)
              end
            end
          end
        end

        describe "after_update" do
          let(:record) { ModelThatIsMultisearchable.create!(some_content: 'random', multisearchable: true) }

          context "when the document is present" do
            before { expect(record.pg_search_documents).to be_present }

            describe "saving the record" do
              context "when the condition is true" do
                it "calls save on the pg_search_documents" do
                  expect { record.update some_content: 'changed' }.to(change { record.pg_search_documents.reload.first.content })
                end

                it "does not create a PgSearch::Document record" do
                  expect { record.save! }.not_to change(PgSearch::Document, :count)
                end
              end

              context "when the condition is false" do
                before { record.multisearchable = false }

                it "calls destroy on the pg_search_documents" do
                  allow(record.pg_search_documents).to receive(:destroy_all)
                  record.save!
                  expect(record.pg_search_documents).to have_received(:destroy_all)
                end

                it "removes its document" do
                  document_ids = record.pg_search_document_ids
                  expect { record.save! }.to change(PgSearch::Document, :count).by(-1)
                  expect { PgSearch::Document.find(document_ids) }.to raise_error(ActiveRecord::RecordNotFound)
                end
              end

              context "with multisearch disabled" do
                before do
                  allow(PgSearch).to receive(:multisearch_enabled?).and_return(false)
                end

                it "does not create a PgSearch::Document record" do
                  allow(record.pg_search_documents).to receive(:find_or_initialize_by)
                  expect { record.save! }.not_to change(PgSearch::Document, :count)
                  expect(record.pg_search_documents).not_to have_received(:find_or_initialize_by)
                end
              end
            end
          end

          context "when the document is missing" do
            before { record.pg_search_documents.destroy_all }

            describe "saving the record" do
              context "when the condition is true" do
                it "creates a PgSearch::Document record" do
                  expect { record.save! }.to change(PgSearch::Document, :count).by(1)
                end

                context "with multisearch disabled" do
                  before { allow(PgSearch).to receive(:multisearch_enabled?).and_return(false) }

                  it "does not create a PgSearch::Document record" do
                    expect { record.save! }.not_to change(PgSearch::Document, :count)
                  end
                end
              end

              context "when the condition is false" do
                before { record.multisearchable = false }

                it "does not create a PgSearch::Document record" do
                  expect { record.save! }.not_to change(PgSearch::Document, :count)
                end
              end
            end
          end
        end

        describe "after_destroy" do
          let(:record) { ModelThatIsMultisearchable.create!(some_content: 'random', multisearchable: true) }

          it "removes its document" do
            document_ids = record.pg_search_document_ids
            expect { record.destroy }.to change(PgSearch::Document, :count).by(-1)
            expect { PgSearch::Document.find(document_ids) }.to raise_error(ActiveRecord::RecordNotFound)
          end
        end
      end
    end

    context "using :unless" do
      with_model :ModelThatIsMultisearchable do
        table do |t|
          t.string :some_content
          t.boolean :not_multisearchable
        end

        model do
          include PgSearch::Model
          multisearchable against: :some_content, unless: ->(record) { record.not_multisearchable? }
        end
      end

      describe "callbacks" do
        describe "after_create" do
          describe "saving the record" do
            context "when the condition is false" do
              let(:record) { ModelThatIsMultisearchable.new(some_content: 'random', not_multisearchable: false) }

              it "creates a PgSearch::Document record" do
                expect { record.save! }.to change(PgSearch::Document, :count).by(1)
              end

              context "with multisearch disabled" do
                before { allow(PgSearch).to receive(:multisearch_enabled?).and_return(false) }

                it "does not create a PgSearch::Document record" do
                  expect { record.save! }.not_to change(PgSearch::Document, :count)
                end
              end
            end

            context "when the condition is true" do
              let(:record) { ModelThatIsMultisearchable.new(some_content: 'random', not_multisearchable: true) }

              it "does not create a PgSearch::Document record" do
                expect { record.save! }.not_to change(PgSearch::Document, :count)
              end
            end
          end
        end

        describe "after_update" do
          let!(:record) { ModelThatIsMultisearchable.create!(some_content: 'random', not_multisearchable: false) }

          context "when the document is present" do
            before { expect(record.pg_search_documents).to be_present }

            describe "saving the record" do
              context "when the condition is false" do
                it "calls save on the pg_search_documents" do
                  expect { record.update some_content: 'changed' }.to(change { record.pg_search_documents.reload.first.content })
                end

                it "does not create a PgSearch::Document record" do
                  expect { record.save! }.not_to change(PgSearch::Document, :count)
                end

                context "with multisearch disabled" do
                  before do
                    allow(PgSearch).to receive(:multisearch_enabled?).and_return(false)
                  end

                  it "does not call save on the document" do
                    expect { record.update some_content: 'changed' }.not_to(change { record.pg_search_documents.reload.first.content })
                  end

                  it "does not create a PgSearch::Document record" do
                    expect { record.save! }.not_to change(PgSearch::Document, :count)
                  end
                end
              end

              context "when the condition is true" do
                before { record.not_multisearchable = true }

                it "calls destroy on the pg_search_documents" do
                  allow(record.pg_search_documents).to receive(:destroy_all)
                  record.save!
                  expect(record.pg_search_documents).to have_received(:destroy_all)
                end

                it "removes its document" do
                  document_ids = record.pg_search_document_ids
                  expect { record.save! }.to change(PgSearch::Document, :count).by(-1)
                  expect { PgSearch::Document.find(document_ids) }.to raise_error(ActiveRecord::RecordNotFound)
                end
              end
            end
          end

          context "when the document is missing" do
            before { record.pg_search_documents.destroy_all }

            describe "saving the record" do
              context "when the condition is false" do
                it "creates a PgSearch::Document record" do
                  expect { record.save! }.to change(PgSearch::Document, :count).by(1)
                end
              end

              context "when the condition is true" do
                before { record.not_multisearchable = true }

                it "does not create a PgSearch::Document record" do
                  expect { record.save! }.not_to change(PgSearch::Document, :count)
                end
              end

              context "with multisearch disabled" do
                before { allow(PgSearch).to receive(:multisearch_enabled?).and_return(false) }

                it "does not create a PgSearch::Document record" do
                  expect { record.save! }.not_to change(PgSearch::Document, :count)
                end
              end
            end
          end
        end

        describe "after_destroy" do
          it "removes its document" do
            record = ModelThatIsMultisearchable.create! some_content: 'random'
            document_ids = record.pg_search_document_ids
            expect { record.destroy }.to change(PgSearch::Document, :count).by(-1)
            expect { PgSearch::Document.find(document_ids) }.to raise_error(ActiveRecord::RecordNotFound)
          end
        end
      end
    end
  end

  describe "a model which is conditionally multisearchable using a Symbol" do
    context "via :if" do
      with_model :ModelThatIsMultisearchable do
        table do |t|
          t.string :some_content
          t.boolean :multisearchable
        end

        model do
          include PgSearch::Model
          multisearchable against: :some_content, if: :multisearchable?
        end
      end

      describe "callbacks" do
        describe "after_create" do
          describe "saving the record" do
            context "when the condition is true" do
              let(:record) { ModelThatIsMultisearchable.new(some_content: 'random', multisearchable: true) }

              it "creates a PgSearch::Document record" do
                expect { record.save! }.to change(PgSearch::Document, :count).by(1)
              end

              context "with multisearch disabled" do
                before { allow(PgSearch).to receive(:multisearch_enabled?).and_return(false) }

                it "does not create a PgSearch::Document record" do
                  expect { record.save! }.not_to change(PgSearch::Document, :count)
                end
              end
            end

            context "when the condition is false" do
              let(:record) { ModelThatIsMultisearchable.new(multisearchable: false) }

              it "does not create a PgSearch::Document record" do
                expect { record.save! }.not_to change(PgSearch::Document, :count)
              end
            end
          end
        end

        describe "after_update" do
          let!(:record) { ModelThatIsMultisearchable.create!(some_content: 'random', multisearchable: true) }

          context "when the document is present" do
            before { expect(record.pg_search_documents).to be_present }

            describe "saving the record" do
              context "when the condition is true" do
                it "calls save on the pg_search_documents" do
                  expect { record.update some_content: 'changed' }.to(change { record.pg_search_documents.reload.first.content })
                end

                it "does not create a PgSearch::Document record" do
                  expect { record.save! }.not_to change(PgSearch::Document, :count)
                end

                context "with multisearch disabled" do
                  before do
                    allow(PgSearch).to receive(:multisearch_enabled?).and_return(false)
                  end

                  it "does not call update the document" do
                    expect { record.update some_content: 'changed' }.not_to(change { record.pg_search_documents.reload.first.content })
                  end

                  it "does not create a PgSearch::Document record" do
                    expect { record.save! }.not_to change(PgSearch::Document, :count)
                  end
                end
              end

              context "when the condition is false" do
                before { record.multisearchable = false }

                it "calls destroy on the pg_search_documents" do
                  allow(record.pg_search_documents).to receive(:destroy_all)
                  record.save!
                  expect(record.pg_search_documents).to have_received(:destroy_all)
                end

                it "removes its document" do
                  document_ids = record.pg_search_document_ids
                  expect { record.save! }.to change(PgSearch::Document, :count).by(-1)
                  expect { PgSearch::Document.find(document_ids) }.to raise_error(ActiveRecord::RecordNotFound)
                end
              end
            end
          end

          context "when the document is missing" do
            before { record.pg_search_documents.destroy_all }

            describe "saving the record" do
              context "with multisearch enabled" do
                before { allow(PgSearch).to receive(:multisearch_enabled?).and_return(true) }

                context "when the condition is true" do
                  it "creates a PgSearch::Document record" do
                    expect { record.save! }.to change(PgSearch::Document, :count).by(1)
                  end
                end

                context "when the condition is false" do
                  before { record.multisearchable = false }

                  it "does not create a PgSearch::Document record" do
                    expect { record.save! }.not_to change(PgSearch::Document, :count)
                  end
                end
              end

              context "with multisearch disabled" do
                before { allow(PgSearch).to receive(:multisearch_enabled?).and_return(false) }

                it "does not create a PgSearch::Document record" do
                  expect { record.save! }.not_to change(PgSearch::Document, :count)
                end
              end
            end
          end
        end

        describe "after_destroy" do
          let(:record) { ModelThatIsMultisearchable.create!(some_content: 'random', multisearchable: true) }

          it "removes its document" do
            document_ids = record.pg_search_document_ids
            expect { record.destroy }.to change(PgSearch::Document, :count).by(-1)
            expect { PgSearch::Document.find(document_ids) }.to raise_error(ActiveRecord::RecordNotFound)
          end
        end
      end
    end

    context "using :unless" do
      with_model :ModelThatIsMultisearchable do
        table do |t|
          t.string :some_content
          t.boolean :not_multisearchable
        end

        model do
          include PgSearch::Model
          multisearchable against: :some_content, unless: :not_multisearchable?
        end
      end

      describe "callbacks" do
        describe "after_create" do
          describe "saving the record" do
            context "when the condition is true" do
              let(:record) { ModelThatIsMultisearchable.new(not_multisearchable: true) }

              it "does not create a PgSearch::Document record" do
                expect { record.save! }.not_to change(PgSearch::Document, :count)
              end
            end

            context "when the condition is false" do
              let(:record) { ModelThatIsMultisearchable.new(some_content: 'random', not_multisearchable: false) }

              it "creates a PgSearch::Document record" do
                expect { record.save! }.to change(PgSearch::Document, :count).by(1)
              end

              context "with multisearch disabled" do
                before { allow(PgSearch).to receive(:multisearch_enabled?).and_return(false) }

                it "does not create a PgSearch::Document record" do
                  expect { record.save! }.not_to change(PgSearch::Document, :count)
                end
              end
            end
          end
        end

        describe "after_update" do
          let!(:record) { ModelThatIsMultisearchable.create!(some_content: 'random', not_multisearchable: false) }

          context "when the document is present" do
            before { expect(record.pg_search_documents).to be_present }

            describe "saving the record" do
              context "when the condition is true" do
                before { record.not_multisearchable = true }

                it "calls destroy on the pg_search_documents" do
                  allow(record.pg_search_documents).to receive(:destroy_all)
                  record.save!
                  expect(record.pg_search_documents).to have_received(:destroy_all)
                end

                it "removes its document" do
                  document_ids = record.pg_search_document_ids
                  expect { record.save! }.to change(PgSearch::Document, :count).by(-1)
                  expect { PgSearch::Document.find(document_ids) }.to raise_error(ActiveRecord::RecordNotFound)
                end
              end

              context "when the condition is false" do
                it "calls save on the pg_search_documents" do
                  expect { record.update some_content: 'changed' }.to(change { record.pg_search_documents.reload.first.content })
                end

                it "does not create a PgSearch::Document record" do
                  expect { record.save! }.not_to change(PgSearch::Document, :count)
                end

                context "with multisearch disabled" do
                  before do
                    allow(PgSearch).to receive(:multisearch_enabled?).and_return(false)
                  end

                  it "does not call save on the document" do
                    expect { record.update some_content: 'changed' }.not_to(change { record.pg_search_documents.reload.first.content })
                  end

                  it "does not create a PgSearch::Document record" do
                    expect { record.save! }.not_to change(PgSearch::Document, :count)
                  end
                end
              end
            end
          end

          context "when the document is missing" do
            before { record.pg_search_documents.destroy_all }

            describe "saving the record" do
              context "with multisearch enabled" do
                before { allow(PgSearch).to receive(:multisearch_enabled?).and_return(true) }

                context "when the condition is true" do
                  before { record.not_multisearchable = true }

                  it "does not create a PgSearch::Document record" do
                    expect { record.save! }.not_to change(PgSearch::Document, :count)
                  end
                end

                context "when the condition is false" do
                  it "creates a PgSearch::Document record" do
                    expect { record.save! }.to change(PgSearch::Document, :count).by(1)
                  end

                  context "with multisearch disabled" do
                    before { allow(PgSearch).to receive(:multisearch_enabled?).and_return(false) }

                    it "does not create a PgSearch::Document record" do
                      expect { record.save! }.not_to change(PgSearch::Document, :count)
                    end
                  end
                end
              end
            end
          end
        end

        describe "after_destroy" do
          let(:record) { ModelThatIsMultisearchable.create!(some_content: 'random', not_multisearchable: false) }

          it "removes its document" do
            document_ids = record.pg_search_document_ids
            expect { record.destroy }.to change(PgSearch::Document, :count).by(-1)
            expect { PgSearch::Document.find(document_ids) }.to raise_error(ActiveRecord::RecordNotFound)
          end
        end
      end
    end
  end
end
# rubocop:enable RSpec/NestedGroups
