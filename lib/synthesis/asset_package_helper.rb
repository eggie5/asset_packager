module Synthesis
  module AssetPackageHelper
    
    def should_merge?
      AssetPackage.merge_environments.include?(RAILS_ENV)
    end

    #wrapper around rails javascript_include_tag to add merged source functionality
    #returns string js tag
    #TODO: Add s3 flag 
    def javascript_include_merged(*sources)
      options = sources.last.is_a?(Hash) ? sources.pop.stringify_keys : { }

      if sources.include?(:defaults) 
        sources = sources[0..(sources.index(:defaults))] + 
          ['prototype', 'effects', 'dragdrop', 'controls'] + 
          (File.exists?("#{RAILS_ROOT}/public/javascripts/application.js") ? ['application'] : []) + 
          sources[(sources.index(:defaults) + 1)..sources.length]
        sources.delete(:defaults)
      end

      sources.collect!{|s| s.to_s}
      
      if should_merge? # get merged source
        sources = AssetPackage.targets_from_sources("javascripts", sources)
      else # get individual sources
        sources = AssetPackage.sources_from_targets("javascripts", sources)
      end
      
      sources.collect {|source| javascript_include_tag(source, options) }.join("\n")
    end

    def stylesheet_link_merged(*sources)
      options = sources.last.is_a?(Hash) ? sources.pop.stringify_keys : { }

      sources.collect!{|s| s.to_s}
      
      if should_merge? # get merged package
        sources = AssetPackage.targets_from_sources("stylesheets", sources)
      else # get individual files
        sources = AssetPackage.sources_from_targets("stylesheets", sources)
      end

      sources.collect { |source|
        source = stylesheet_path(source)
        tag("link", { "rel" => "Stylesheet", "type" => "text/css", "media" => "screen", "href" => source }.merge(options))
      }.join("\n")    
    end
  end
end