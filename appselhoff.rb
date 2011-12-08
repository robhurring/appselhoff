framework 'Cocoa'

module Appselhoff
  extend self
  
  trap(:INT){ self.terminate }
  
  def run!
    active_app = []
    @watcher = Watcher.new
    
    # watch for activation notifications
    @watcher.subscribe :did_activate_application do |app|
      name = app.localizedName

      unless active_app.empty?
        old_app, old_time = active_app
        old_app_name = old_app.localizedName
        usage = (Time.now - old_time).round

        if usage > 0
          session = Session.find_by_name(old_app_name) || Session.make
          session.application = old_app_name
          session.seconds ||= 0
          session.seconds += usage
          puts "Used: #{session.application} for #{usage} second(s) [#{session.seconds}s total usage]"
        end
      end

      active_app = [app, Time.now]
    end

    NSRunLoop.currentRunLoop.run
  end

  def terminate
    if @watcher
      @watcher.cleanup!
      DataStore.save
    end
    
    exit 0
  end

  # http://developer.apple.com/library/mac/#documentation/Cocoa/Reference/ApplicationKit/Classes/NSWorkspace_Class/Reference/Reference.html
  class Watcher
    Notifications = {
      will_launch_application: NSWorkspaceWillLaunchApplicationNotification,
      did_launch_application: NSWorkspaceDidLaunchApplicationNotification,
      did_terminate_application: NSWorkspaceDidTerminateApplicationNotification,
      did_activate_application: NSWorkspaceDidActivateApplicationNotification,
      did_deactivate_application: NSWorkspaceDidDeactivateApplicationNotification,
      did_hide_application: NSWorkspaceDidHideApplicationNotification,
      did_unhide_application: NSWorkspaceDidUnhideApplicationNotification,
      session_did_become_activate: NSWorkspaceSessionDidBecomeActiveNotification,
      session_did_resign_active: NSWorkspaceSessionDidResignActiveNotification,
      did_hide_application: NSWorkspaceDidHideApplicationNotification,
      did_rename_volume: NSWorkspaceDidRenameVolumeNotification,
      did_mount: NSWorkspaceDidMountNotification,
      will_unmount: NSWorkspaceWillUnmountNotification,
      did_unmount: NSWorkspaceDidUnmountNotification,
      did_perform_file_operation: NSWorkspaceDidPerformFileOperationNotification,
      did_change_file_labels: NSWorkspaceDidChangeFileLabelsNotification,
      active_space_did_change: NSWorkspaceActiveSpaceDidChangeNotification,
      did_wake: NSWorkspaceDidWakeNotification,
      will_power_off: NSWorkspaceWillPowerOffNotification,
      will_sleep: NSWorkspaceWillSleepNotification,
      screen_did_sleep: NSWorkspaceScreensDidSleepNotification,
      screen_did_wake: NSWorkspaceScreensDidWakeNotification
    }
    
    def initialize
      @subscriptions = []
      @observed = []
    end
    
    def subscribe(notification, &callback)
      @subscriptions << {notification: Notifications[notification], callback: callback}
      observe notification
    end
    
    def cleanup!
      remove_observers
    end
    
  private
  
    def dispatch(notification)
      app = notification.userInfo['NSWorkspaceApplicationKey']
      @subscriptions.each do |sub|
        next if sub[:notification].to_s != notification.name
        sub[:callback].call(app)
      end
    end
    
    def remove_observers
      nc = NSWorkspace.sharedWorkspace.notificationCenter
      nc.removeObserver(self)
    end
    
    def observe(notification)
      return if @observed.include?(notification)
      
      nc = NSWorkspace.sharedWorkspace.notificationCenter
      if nc.addObserver self, selector: 'dispatch:', name: Notifications[notification], object: nil
        @observed << notification
      end
    end
  end
  
  class Session < NSManagedObject    
    def self.find_by_name(app_name)
      results = self.where('application = %@', app_name)
      results.empty? ? nil : results.first
    end
    
    def self.make
      context = Appselhoff::DataStore.context
      desc = NSEntityDescription.entityForName('Session', inManagedObjectContext: context)
      session = Session.alloc.initWithEntity(desc, insertIntoManagedObjectContext: context)
    end

    def self.where(*args)
      context = Appselhoff::DataStore.context
      entity = NSEntityDescription.entityForName('Session', inManagedObjectContext: context)
      pred = NSPredicate.predicateWithFormat *args

      request = NSFetchRequest.alloc.init 
      request.entity = entity
      request.predicate = pred

      error = Pointer.new_with_type('@')
      result = context.executeFetchRequest(request, error:error)
    end
  end
  
  class DataStore
    DataFile = 'data.db'
    StoreType = NSSQLiteStoreType
    
    def self.save
      error = Pointer.new_with_type('@')
      self.context.save(error)
    end

    def self.managed_object_model
      @model ||= begin
        model = NSManagedObjectModel.new

        # create the entity
        session_entity = NSEntityDescription.new
        session_entity.name = "Session"
        session_entity.managedObjectClassName = "Session"
        model.entities = [session_entity]

        app_attribute = NSAttributeDescription.new
        app_attribute.name = "application"
        app_attribute.attributeType = NSStringAttributeType
        app_attribute.optional = false

        sec_attribute = NSAttributeDescription.new
        sec_attribute.name = "seconds"
        sec_attribute.attributeType = NSInteger32AttributeType
        sec_attribute.defaultValue = 0

        session_entity.properties = [app_attribute, sec_attribute]

        model
      end
    end
    
    def self.context
      @context ||= begin
        context = NSManagedObjectContext.new
        
        coordinator = NSPersistentStoreCoordinator.alloc.initWithManagedObjectModel(self.managed_object_model)
        context.persistentStoreCoordinator = coordinator

        url = NSURL.fileURLWithPath(DataFile)

        # pointer trick, translate the NSError *error declaration
        error = Pointer.new_with_type('@')
        new_store = coordinator.addPersistentStoreWithType(StoreType, configuration: nil, URL: url, options: nil, error: error)
            
        unless new_store
          puts "Store configuration error"
        end 
        
        context
      end
    end
  end
end

at_exit{ Appselhoff.run! }