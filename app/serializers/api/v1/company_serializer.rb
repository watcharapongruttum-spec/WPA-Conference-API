class Api::V1::CompanySerializer < ActiveModel::Serializer
  attributes :id, :name, :country, :email
end
