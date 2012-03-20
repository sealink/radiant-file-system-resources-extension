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
            dump_resource(e)
            e.destroy
          end
        end
      end

      def dump_resource(resource)
        if resource.content.present?
          filename = Rails.root.join('tmp',resource.name + '.radius.archive')
          puts "     Previously shadowed content archived to #{filename}"
          File.open(filename, 'w') do |file|
            file.write(resource.content)
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
