module Synthesis
  class AssetPackage

    # class variables
    @@asset_packages_yml = $asset_packages_yml || 
      (File.exists?("#{RAILS_ROOT}/config/asset_packages.yml") ? YAML.load_file("#{RAILS_ROOT}/config/asset_packages.yml") : nil)
  
    # singleton methods
    class << self
      
      def merge_environments=(environments)
        @@merge_environments = environments
      end
      
      def merge_environments
        @@merge_environments ||= ["production"]
      end
      
      def parse_path(path)
        /^(?:(.*)\/)?([^\/]+)$/.match(path).to_a
      end

      def find_by_type(asset_type)
        @@asset_packages_yml[asset_type].collect { |p| self.new(asset_type, p) }
      end

      # "javascripts", "management"
      def find_by_target(asset_type, target)
        package_hash = @@asset_packages_yml[asset_type].find {|p| p.keys.first == target }
        package_hash ? self.new(asset_type, package_hash) : nil
      end

      def find_by_source(asset_type, source)
        path_parts = parse_path(source)
        package_hash = @@asset_packages_yml[asset_type].find do |p|
          key = p.keys.first
          p[key].include?(path_parts[2]) && (parse_path(key)[1] == path_parts[1])
        end
        package_hash ? self.new(asset_type, package_hash) : nil
      end

      #"javascipts" [asdf.js, asdf.js]
      def targets_from_sources(asset_type, sources)
        package_names = []
        sources.each do |source|
          package = find_by_target(asset_type, source) || find_by_source(asset_type, source)
          package_names << (package ? package.current_file : source)
        end
        package_names.uniq!
        return package_names
      end

      def sources_from_targets(asset_type, targets)
        source_names = Array.new
        targets.each do |target|
          package = find_by_target(asset_type, target)
          source_names += (package ? package.sources.collect do |src|
            src.gsub!(/^public/,'')
            src
          end : target.to_a)
        end
        source_names.uniq
      end

      def build_all
        @@asset_packages_yml.keys.each do |asset_type|
          @@asset_packages_yml[asset_type].each { |p| self.new(asset_type, p).build }
        end
      end

      def delete_all
        @@asset_packages_yml.keys.each do |asset_type|
          @@asset_packages_yml[asset_type].each { |p| self.new(asset_type, p).delete_all_builds }
        end
      end

      def create_yml
        unless File.exists?("#{RAILS_ROOT}/config/asset_packages.yml")
          asset_yml = Hash.new

          asset_yml['javascripts'] = [{"base" => build_file_list("#{RAILS_ROOT}/public/javascripts", "js")}]
          asset_yml['stylesheets'] = [{"base" => build_file_list("#{RAILS_ROOT}/public/stylesheets", "css")}]

          File.open("#{RAILS_ROOT}/config/asset_packages.yml", "w") do |out|
            YAML.dump(asset_yml, out)
          end

          log "config/asset_packages.yml example file created!"
          log "Please reorder files under 'base' so dependencies are loaded in correct order."
        else
          log "config/asset_packages.yml already exists. Aborting task..."
        end
      end

    end
    
    # instance methods
    attr_accessor :asset_type, :target, :target_dir, :sources
  
    def initialize(asset_type, package_hash)
      #package hash: {"public/management/javascripts/management_all.js"=>["public/javascripts/prototype.js", "public/management/javascripts/tabber.js", "public/management/javascripts/management.js", "public/management/javascripts/MMSService.js", "public/management/javascripts/swfuploadr5.js", "public/management/javascripts/snackWizard.js", "public/management/javascripts/snackManager.js", "public/management/javascripts/uploadQueue.js", "public/management/javascripts/videoInspector.js", "public/management/javascripts/validation.js", "public/management/javascripts/app-settings.js", "public/management/javascripts/AC_QuickTime.js", "public/management/javascripts/sendInterface.js", "public/management/javascripts/lightbox.js", "public/management/javascripts/reports.js", "public/management/javascripts/Snack.js", "public/management/javascripts/swfobject.js", "public/management/javascripts/event_mixins.js", "public/management/javascripts/preferences.js", "public/javascripts/scriptaculous.js", "public/javascripts/effects.js", "public/javascripts/controls.js", "public/management/javascripts/calendar_date_select.js", "public/management/javascripts/sorttable.js", "public/management/javascripts/protoload.js", "public/management/javascripts/date.js"]}
      target_parts = self.class.parse_path(package_hash.keys.first)
      @target_dir = target_parts[1].to_s
      @target = target_parts[2].to_s
      @sources = package_hash[package_hash.keys.first]
      @asset_type = asset_type
      @asset_path = ($asset_base_path ? "#{$asset_base_path}/" : "#{RAILS_ROOT}/") + "#{@target_dir}"
      @extension = get_extension
      #@match_regex = Regexp.new("\\A#{@target}\\.+.#{@extension}\\z")
      @match_regex = Regexp.new("\\.*_all.#{@extension}\\z")
      
    end
  
    def current_file
      #return "/management/javascripts/management_all.js"
      #@target_dir: public/management/javascripts
      #@asset_path: /Users/eggie5/Sites/tap_svn/branches/rename/public/management/javascripts
      
      file = @target_dir + "/" + Dir.new(@asset_path).entries.delete_if { |x| ! (x =~ @match_regex) }.sort.reverse[0].chomp(".#{@extension}")
      file.gsub!(/^public/,'')
      return file
      #return "/management/javascripts/management_all.js"
    end

    def build
      delete_old_builds
      create_new_build
    end
  
    def delete_old_builds
      Dir.new(@asset_path).entries.delete_if { |x| ! (x =~ @match_regex) }.each do |x|
        File.delete("#{@asset_path}/#{x}") unless x.index(revision.to_s)
      end
    end

    def delete_all_builds
      Dir.new(@asset_path).entries.delete_if { |x| ! (x =~ @match_regex) }.each do |x|
        File.delete("#{@asset_path}/#{x}")
      end
    end

    private
      def revision
        unless @revision
          revisions = [1]
          @sources.each do |source|
            revisions << get_file_revision("#{@asset_path}/#{source}.#{@extension}")
          end
          @revision = revisions.max
        end
        @revision
      end
  
      def get_file_revision(path)
        if File.exists?(path)
          begin
            `svn info #{path}`[/Last Changed Rev: (.*?)\n/][/(\d+)/].to_i
          rescue # use filename timestamp if not in subversion
            File.mtime(path).to_i
          end
        else
          0
        end
      end

      def create_new_build
        path = "#{@asset_path}/#{@target}"
        # if File.exists?(path)
        #         log "Latest version already exists: #{path}"
        #       else
          #creates the compressed file at path
          File.open(path, "w") {|f| f.write(compressed_file) }
          log "Created #{path}"
        # end
      end

      #merges all file in package to string then passes to compression code
      def merged_file
        merged_file = "" #all sources will be appended to this string
        
        @sources.each do |source| 
          path = "#{RAILS_ROOT}/#{source}" #input file
          File.open(path, "r") do |f| 
            merged_file += f.read + "\n" 
          end
        end
        merged_file
      end
    
      def compressed_file
        case @asset_type
          when "javascripts" then compress_js(merged_file)
          when "stylesheets" then compress_css(merged_file)
        end
      end

      # def compress_js(source)
      #   jsmin_path = "#{RAILS_ROOT}/vendor/plugins/asset_packager/lib"
      #   tmp_path = "#{RAILS_ROOT}/tmp/#{@target}_#{revision}"
      # 
      #   # write out to a temp file
      #   File.open("#{tmp_path}_uncompressed.js", "w") {|f| f.write(source) }
      # 
      #   # compress file with JSMin library
      #   `ruby #{jsmin_path}/jsmin.rb <#{tmp_path}_uncompressed.js >#{tmp_path}_compressed.js \n`
      # 
      #   # read it back in and trim it
      #   result = ""
      #   File.open("#{tmp_path}_compressed.js", "r") { |f| result += f.read.strip }
      #   
      #   # delete temp files if they exist
      #   File.delete("#{tmp_path}_uncompressed.js") if File.exists?("#{tmp_path}_uncompressed.js")
      #   File.delete("#{tmp_path}_compressed.js") if File.exists?("#{tmp_path}_compressed.js")
      # 
      #   result
      # end
      
      #compress file using YUI, then return as string
      def compress_js(source)
        yui_compressor_path = "#{RAILS_ROOT}/lib/yuicompressor-2.3.1.jar"
        tmp_path = "#{RAILS_ROOT}/tmp/#{@target}_#{revision}"
      
        # write out to a temp file
        File.open("#{tmp_path}_uncompressed.js", "w") {|f| f.write(source) }
      
        # compress file with JSMin library
        `java -jar #{yui_compressor_path} #{tmp_path}_uncompressed.js --nomunge -o #{tmp_path}_compressed.js`
        #`ruby #{jsmin_path}/jsmin.rb <#{tmp_path}_uncompressed.js >#{tmp_path}_compressed.js \n`

        # append to merged js master file
        result = ""
        File.open("#{tmp_path}_compressed.js", "r") { |f| result += f.read.strip }
  
        # delete temp files if they exist
        File.delete("#{tmp_path}_uncompressed.js") if File.exists?("#{tmp_path}_uncompressed.js")
        File.delete("#{tmp_path}_compressed.js") if File.exists?("#{tmp_path}_compressed.js")

        result
      end
  
      #returns string of css file
      def compress_css(source)
        # source.gsub!(/\s+/, " ")           # collapse space
        #         source.gsub!(/\/\*(.*?)\*\/ /, "") # remove comments - caution, might want to remove this if using css hacks
        #          source.gsub!(/\} /, "}\n")         # add line breaks
        #          source.gsub!(/\n$/, "")            # remove last break
        #         # source.gsub!(/ \{ /, " {")         # trim inside brackets
        #         # source.gsub!(/; \}/, "}")          # trim inside brackets
        #         source
        
         yui_compressor_path = "#{RAILS_ROOT}/lib/yuicompressor-2.3.5.jar"
          tmp_path = "#{RAILS_ROOT}/tmp/#{@target}_#{revision}"
          
        # write out to a temp file
          File.open("#{tmp_path}_uncompressed.css", "w") {|f| f.write(source) }
          
          `java -jar #{yui_compressor_path} #{tmp_path}_uncompressed.css -o #{tmp_path}_compressed.css`
          
      
          result = ""
         File.open("#{tmp_path}_compressed.css", "r") { |f| result += f.read.strip }
         result
      end

      def get_extension
        case @asset_type
          when "javascripts" then "js"
          when "stylesheets" then "css"
        end
      end
      
      def log(message)
        self.class.log(message)
      end
      
      def self.log(message)
        puts message
      end

      def self.build_file_list(path, extension)
        re = Regexp.new(".#{extension}\\z")
        file_list = Dir.new(path).entries.delete_if { |x| ! (x =~ re) }.map {|x| x.chomp(".#{extension}")}
        # reverse javascript entries so prototype comes first on a base rails app
        file_list.reverse! if extension == "js"
        file_list
      end
   
  end
end
