namespace :radiant do
  namespace :extensions do
    namespace :file_system_resources do

      desc "Runs the migration of the Fs Resources extension"
      task :migrate => :environment do
        require 'radiant/extension_migrator'
        if ENV["VERSION"]
          FileSystemResourcesExtension.migrator.migrate(ENV["VERSION"].to_i)
        else
          p FileSystemResourcesExtension.migrations_path
          FileSystemResourcesExtension.migrator.migrate
        end
      end

      namespace :migrate do
        task :rollback => :environment do
          step = ENV['STEP'] ? ENV['STEP'].to_i : 1
          FileSystemResourcesExtension.migrator.rollback(FileSystemResourcesExtension.migrations_path, step)
        end
      end

      desc "Copies public assets of the Fs Resources to the instance public/ directory."
      task :update => :environment do
        is_svn_or_dir = proc {|path| path =~ /\.svn/ || File.directory?(path) }
        puts "Copying assets from FileSystemResourcesExtension"
        Dir[FileSystemResourcesExtension.root + "/public/**/*"].reject(&is_svn_or_dir).each do |file|
          path = file.sub(FileSystemResourcesExtension.root, '')
          directory = File.dirname(path)
          mkdir_p RAILS_ROOT + directory, :verbose => false
          cp file, RAILS_ROOT + path, :verbose => false
        end
        unless FileSystemResourcesExtension.root.starts_with? RAILS_ROOT # don't need to copy vendored tasks
          puts "Copying rake tasks from FileSystemResourcesExtension"
          local_tasks_path = File.join(RAILS_ROOT, %w(lib tasks))
          mkdir_p local_tasks_path, :verbose => false
          Dir[File.join FileSystemResourcesExtension.root, %w(lib tasks *.rake)].each do |file|
            cp file, local_tasks_path, :verbose => false
          end
        end
        %w(layouts snippets).each do |dir|
          FileUtils.mkdir_p(Rails.root.join('app','templates',dir))
        end
      end

      desc "Registers file system resources in the database (needed only when added/removed, not on edit)."
      task :register => :environment do
        [Layout, Snippet].each do |klass|
          seen = []
          fs_name = klass.name.downcase.pluralize

          templates(fs_name).each do |f|
            filename = File.basename(f, ".radius")
            seen << filename
            resource = klass.find_by_name(filename)
            if resource
              next if resource.file_system_resource?
              puts "Registered #{klass.name} #{filename}. WARNING: Will shadow existing database content!"
              resource.update_attribute(:file_system_resource, true)
            else
              klass.create!(:name => filename, :file_system_resource => true)
              puts "Registered #{klass.name} #{filename}."
            end
          end
          klass.find_all_by_file_system_resource(true).reject{|e| seen.include?(e.filename)}.each do |e|
            puts "Removing #{klass.name} #{e.filename} (no longer exists on file system)."
            archived_name = dump_resource(e)
            puts "--> Previously shadowed content archived to #{archived_name.relative_path_from(Rails.root)}" if archived_name
            e.destroy
          end
        end
      end

      desc "Extracts specified database layouts and/or snippets to Fs Resources "
      task :extract => :environment do
        [Layout, Snippet].each do |klass|
          fs_dir = klass.name.downcase.pluralize
          ENV[fs_dir].to_s.split(',').each do |resource_name|
            resource = klass.find_by_name(resource_name)
            if resource
              filename = dump_resource(resource, "app/templates/#{fs_dir}")
              puts "extracted #{klass.name.downcase} named '#{resource_name}' to #{filename.relative_path_from(Rails.root)}"
              resource.update_attribute(:file_system_resource, true)
            else
              puts "WARNING: Unable to find #{klass.name.downcase} named '#{resource_name}' to extract!"
            end
          end
        end
      end


      def dump_resource(resource, dir='tmp')
        if resource.content.present?
          Rails.root.join(dir, resource.name + '.radius').tap do |filename|
            File.open(filename, 'w') do |file|
              file.write(resource.content)
            end
          end
        end
      end

      def templates(dir)
        old_path = Rails.root.join('radiant', dir)
        new_path = Rails.root.join('app', 'templates', dir)
        if (File.directory?(old_path))
          Dir[old_path.join('*.radius')].each do |f|
            path = Pathname.new(f)
            puts "WARNING: Please move #{path.relative_path_from(Rails.root)} to #{new_path.join(path.basename).relative_path_from(Rails.root)}"
          end
        end
        Dir[new_path.join('*.radius')]
      end

    end
  end
end
