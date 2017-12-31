require 'aws-sdk'

module Aws::EC2 end

class Aws::EC2::Handler

  def self.ec2_client
    @ec2_client ||= Aws::EC2::Client.new
  end

  def self.ec2_resource
    @ec2_resource ||= Aws::EC2::Resource.new
  end

  def self.instances(filters: {})
    filter_params = filters.map do |key, values|
      {
        name: key.to_s,
        values: Array(values),
      }
    end
    ec2_resource.instances({
      filters: filter_params,
    })
  end

  def self.running_instances(tag_name: nil, tag_role: nil)
    filters = {
      'instance-state-name' => 'running',
    }
    filters['tag:Name'] = tag_name if tag_name
    filters['tag:Role'] = tag_role if tag_role
    self.instances(filters: filters)
  end

end
