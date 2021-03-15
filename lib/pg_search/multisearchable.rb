# frozen_string_literal: true

require "active_support/core_ext/class/attribute"

module PgSearch
  module Multisearchable
    def self.included(mod)
      mod.class_eval do
        has_many :pg_search_documents,
                 as: :searchable,
                 class_name: "PgSearch::Document",
                 dependent: :destroy

        after_save :update_pg_search_documents,
                   if: -> { PgSearch.multisearch_enabled? }

        after_destroy :clear_search_documents
      end
    end

    def searchable_text(language)
      Array(pg_search_multisearchable_options[:against])
        .map { |symbol| searchable_content(symbol, language) }
        .join(" ")
    end

    def search_languages
      pg_search_multisearchable_options[:languages]&.to_proc&.call(self) || [I18n.default_locale]
    end

    def pg_search_documents_attrs
      search_languages.map do |language|
        {
          content: searchable_text(language),
          language: language,
          sort_content: searchable_content(sort_content_attribute, language)
        }.tap do |h|
          if (attrs = pg_search_multisearchable_options[:additional_attributes])
            h.merge! attrs.to_proc.call(self)
          end
        end
      end
    end

    def should_update_pg_search_documents?
      return false if pg_search_documents.none?

      conditions = Array(pg_search_multisearchable_options[:update_if])
      conditions.all? { |condition| condition.to_proc.call(self) }
    end

    def update_pg_search_documents
      if_conditions = Array(pg_search_multisearchable_options[:if])
      unless_conditions = Array(pg_search_multisearchable_options[:unless])

      should_have_documents =
        if_conditions.all? { |condition| condition.to_proc.call(self) } &&
        unless_conditions.all? { |condition| !condition.to_proc.call(self) }

      if should_have_documents
        create_or_update_pg_search_documents
      else
        clear_search_documents
      end
    end

    def create_or_update_pg_search_documents
      pg_search_documents_attrs.each do |attr|
        document = pg_search_documents.find_or_initialize_by(language: attr[:language])
        if attr[:content].blank?
          document.destroy
        else
          document.update(attr) unless document.persisted? && !should_update_pg_search_documents?
        end
      end
    end

    def sort_content_attribute
      pg_search_multisearchable_options[:sortable] || Array(pg_search_multisearchable_options[:against]).first
    end

    def clear_search_documents
      pg_search_documents&.destroy_all
    end
  end
end
