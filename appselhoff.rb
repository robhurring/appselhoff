framework 'Cocoa'

module Appselhoff
  extend self
  
  trap(:INT){ self.terminate }
  
  def run!
    @watcher = Watcher.new(self)
    NSRunLoop.currentRunLoop.run
  end
  
  def terminate
    DataStore.save
    exit 0
  end
  
  # http://developer.apple.com/library/mac/#documentation/Cocoa/Reference/ApplicationKit/Classes/NSWorkspace_Class/Reference/Reference.html
  class Watcher
    Observe = {
      NSWorkspaceDidActivateApplicationNotification => 'active:'
    }
    
    def initialize(delegate)
      @delegate = delegate
      @active = []
      add_observers
    end

    def active(notice)
      app = notice_app(notice)
      name = app.localizedName
      
      unless @active.empty?
        old_app, old_time = @active
        usage = (Time.now - old_time).round
        
        unless usage.zero?
          session = Session.find_by_name(old_app) || Session.make
          session.application = old_app
          session.seconds ||= 0
          session.seconds += usage

          puts "Used: #{session.application} for #{usage} second(s) [#{session.seconds}s total usage]"
        end
      end
      
      @active = [name, Time.now]
    end

  private
  
    def notice_app(notice)
      notice.userInfo['NSWorkspaceApplicationKey']
    end
  
    def add_observers
      nc = NSWorkspace.sharedWorkspace.notificationCenter
      Observe.each do |notification, selector|
        nc.addObserver self, selector: selector, name: notification, object: nil
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

# p Appselhoff::Session.make