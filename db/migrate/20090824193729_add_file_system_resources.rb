class AddFileSystemResources < ActiveRecord::Migration
  def self.up
    add_column :layouts, :file_system_resource, :boolean
  end

  def self.down
    remove_column :layouts, :file_system_resource
  end
end
