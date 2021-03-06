# coding: utf-8
class Topic
  include Mongoid::Document
  include BaseModel
  
  attr_accessor :current_user_id, :cover_changed
  field :name
  field :summary
  field :cover
  mount_uploader :cover, CoverUploader

  field :asks_count, :type => Integer, :default => 0

  index :name
  has_many :logs, :class_name => "Log", :foreign_key => "target_id"
  
  # Followers
  references_and_referenced_in_many :followers, :stored_as => :array, :inverse_of => :followed_topics, :class_name => "User"

  validates_presence_of :name
  validates_uniqueness_of :name, :case_insensitive => true

  redis_search_index(:title_field => :name)

  # 敏感词验证
  before_validation :check_spam_words
  def check_spam_words
    if self.spam?("name")
      return false
    end

    if self.spam?("summary")
      return false
    end
  end

  # Hack 上传图片，用于记录 cover 是否改变过
  def cover=(obj)
    super(obj)
    self.cover_changed = true
  end

  before_update :update_log
  def update_log
    return false if self.current_user_id.blank?
    insert_action_log("EDIT") if self.cover_changed or self.summary_changed?
  end

  def self.save_topics(topics, current_user_id)
    new_topics = []
    topics.each do |item|
      topic = find_by_name(item.strip)
      # find_or_create_by(:name => item.strip)
      if topic.nil?
        topic = create(:name => item.strip)
        begin
          log = TopicLog.new
          log.user_id = current_user_id
          log.title = topic.name
          log.topic = topic
          log.action = "NEW"
          log.diff = ""
          log.save
        rescue Exception => e

        end
      end
      new_topics << topic.name
    end
    new_topics
  end

  def self.find_by_name(name)
    find(:first,:conditions => {:name => /^#{name.downcase}$/i})
  end

  def self.search_name(name, options = {})
    limit = options[:limit] || 10
    where(:name => /#{name}/i ).desc(:asks_count).limit(limit)
  end

  protected
    def insert_action_log(action)
      begin
        log = TopicLog.new
        log.user_id = self.current_user_id
        log.title = self.name
        log.target_id = self.id
        log.target_attr = (self.cover_changed == true ? "COVER" : (self.summary_changed? ? "SUMMARY" : "")) if action == "EDIT"
        log.action = action
        log.diff = ""
        log.save
      rescue Exception => e
        Rails.logger.info { "#{e}" } 
      end
    end
end
