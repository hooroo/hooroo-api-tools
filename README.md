
# Http API Tools

Provides fast serialization/deserialization of models with simple model attribute definition in client apps.

Adheres to the ID Based Json API Spec - http://jsonapi.org/format/#id-based-json-api for serialization

## Installation

Add this line to your application's Gemfile:

    gem 'http_api_tools'

And then execute:

    $ bundle

Or install it yourself as:

    $ gem install http_api_tools


## Usage
At a high level this gem provides serialization of models (active model or otherwise), deserialization of the serialized json and a way to declaritively create basic models in clients with basic type coercion.

It has been written to work as a whole where the producer and client of the api are both maintained by the same development team. Conventions are used throughout to keep things simple. At this stage, breaking these conventions isn't supported in many cases but the gem can be extended towards this goal as the needs arise. Please see the note on performance in the section on contributing at the end of this document.


### Config

Create an app initializer in `config/initializers/http_api_tools.rb` with the following.

```ruby
HttpApiTools::SerializerLoader.preload
```

### Serialization
There are two supported serialization formats - sideloading and nesting. Both formats maintain an identical api and
usage pattern while serializing in different ways. While it is possible to provide both formats in an application, it's likely you'd stick to one as the general philosophy is that a resource should always be represented in the same way.

To use a serializer in a controller you should instantiate an instance of the serializer for the top level type you're serializing and pass it to render.

`render json: UserSerializer.new(user)`


#### Nesting vs Sideloading
The big difference between these formats is that nesting represents the relationships between resources implicitly in it's structure whereas sideloading is a flattened structure with relationships represented via linked identifiers. The details of these formats will be described in more detail below.


#### Serializer Definition

This serializer will either be defined as a nesting or sideloading serializer depening on the serializer it is based on.

```ruby
class UserSerializer

  include HttpApiTools::Sideloading::JsonSerializer

end
```

```ruby
class UserSerializer

  include HttpApiTools::Nesting::JsonSerializer

end
```


Serializers can define attributes and relationships to be serialized.

```ruby
class UserSerializer

  include HttpApiTools::Sideloading::JsonSerializer

  serializes(User)
  attributes :id, :first_name, :last_name
  has_many :posts
  has_one :profile

end
```

If you want to serialize any composite attributes they can be defined as a method on the serializer and defined as an attribute. The object being serialized can be accessed via the `serializable` method on the serializer.

```ruby
class UserSerializer

  include HttpApiTools::Sideloading::JsonSerializer

  serializes(User)
  attributes :id, :first_name, :last_name, :full_name

  def full_name
    "#{serializable.first_name} #{serializable.last_name}"
  end

end
```

#### JSON Structure

##### Sideloading

By default, only the ids of related objects will be serialized. For serializers using a 'sideloading' approach, these relationships and their ids will be added to the `links` hash.


```javascript
{
 "users": [{
    "id": 1,
    "first_name": "John",
    "last_name": "Smith",
    "links" {
      "profile": 2,
      "posts": [3, 4]
    }
 }]
}
```

##### Nesting
As with sideloading serializers, by default, only the ids of related objects will be serialized. For serializers using a 'nesting' approach, these relationships and their ids will be inlined using their _id / _ids attribute name suffix.



```javascript
{
 "users": [{
    "id": 1,
    "first_name": "John",
    "last_name": "Smith",
    "profile_id": 2,
    "post_ids": [3, 4]
 }]
}
```

One advantage to this approach is that it's always clear what relationships exist for a resource, even if you don't
include the resources themselves in the response.

##### Serializing related resources via includes
Often it will be desirable to load related data to save on requests. This can be done when creating the top level serializer using the same approach ActiveRecord uses for including relationships in queries.

`UserSerializer.new(user).includes(:profile, { posts: [:comments] })`

Which produces the following json when sideloaded:

```javascript
{
 "users": [{
    "id": 1,
    "first_name": "John",
    "last_name": "Smith",
    "links": {
      "profile": 2,
      "posts": [3, 4]
    }
 }],
 "linked": {
   "profiles": [
    {
      "id": 2,
      //...
    }
   ],

   posts: [
    {
      "id": 3,
      "links": {
        "user": 1,
        "comments": [5]
      }
      //...
    },
    {
      "id": 4,
      "links": {
        "user": 1,
        "comments": []
      }
      //...
    }
   ],
   "comments": [
    "id": 5,
    "links": {
        "post": 3
    }
    //...
   ]
  }

}
```

and the following when nested:

```javascript
{
 "users": [{
    "id": 1,
    "first_name": "John",
    "last_name": "Smith",
    "profile": {
      "id": 2,
    },
    posts: [
      {
        "id": 3,
        "user_id": 1
        "comments": [
          {
            "id": 5,
            "post_id": 3
          }
        ]
      },
      {
        "id": 4,
        "user_id": 1
        "comments": []
      }
    ]
  }]
}
```

One benefit to sideloading over nesting resources is that if the same resource is referenced multiple times, it only needs to be serialized once. Depending on your data, this may or may not be significant.

##### Including related resources via the url
It's possible to determine what resources to include by providing a query string parameter:

`http://example.com/users/1?include=comments,posts.comments`

This can be parsed using:

`relation_includes = HttpApiTools::RelationIncludes.from_params(params)`

and splat into the serializer includes:

`UserSerializer.new(user).includes(*relation_includes)`

and/or active record queries:

`User.find(params[:id]).includes(*relation_includes.for_query(UserSerializer))`

When providing the includes for an active record query, we actually want a deeper set of includes in order to account for the ids fetched for has_many relationships. If we passed the same set of includes to the query as we pass to the serializer, we'd end up with n+1 queries when fetching the ids for the has_many relationships.

Calling `relation_includes.for_query(UserSerializer)` will figure out the minimum set of includes that are required based on the following:

* The models and their relationships
* The relationships actually being serialized

**** Note that this particular API is pretty rough at the moment and likely to change once we find a nicer way of describing this feature.

##### Restricting what is included
Once you expose what can be included as a query string parameter you risk exposing too much information or poorly considered api calls that fetch too much. This can be countered by defining what is `includable` for each serializer when it's being used as the root serializer for a json response.

```ruby
class UserSerializer

  include HttpApiTools::Nesting::JsonSerializer

  serializes(User)

  attributes :id, :first_name, :last_name, :full_name

  has_many :posts
  has_many :comments

  includable(:profile, {:posts, [:comments]})

end
```

This will ensure that regardless of what is declared in the `include` param, no more than the allowable includes are ever returned.

To help in documenting what is includable, both the includable and included relations are returned in the meta data of the response.

```javascript
"meta": {
  "type": "user",
  "root_key": "users",
  "includable": "profile,posts,posts.comments"
  "included": "posts"
}
```

##### Dynamic attribute and relationship excludes
Sometimes an attribute or relationship needs to be excluded from the payload based on a runtime condition but it makes sense to define this on the serializer itself so it always applies.  For example, an attribute might be available to a particular caller of the api but not to others.

This can be achieved via the `exclude_when` configuration on attributes or relations.

```ruby
class UserSerializer

  include HttpApiTools::Nesting::JsonSerializer

  serializes(User)

  attribute :id
  attribute :username
  attribute :first_name
  attribute :last_name
  attribute :tax_file_number, exclude_when: :exclude_tax_file_number?

  has_many :posts
  has_many :comments
  has_one :notes, exclude_when: -> (serializable) { CurrentUser.user_name != serializable.username }

  def exclude_tax_file_number?
    !CurrentUser.has_role?(:admin) && CurrentUser.user_name != serializable.username
  end

end
```

This example shows the tax file number being excluded via the `exclude_tax_file_number?` method when the current user is not the user being serialized. The second example shows he use of a proc to implemenet the exclusion logic.


#### Meta data
Every request will also contain a special meta attribute which could be augmented with various additional pieces
of meta-data. At this point, it will always return the `type` and `root_key` for the current request.  Eg:

```javascript
{
  "meta": {
    "type": "user",
    "root_key": "users"
  },
  "users": [{
    "id": 1,
    "first_name": "John",
    "last_name": "Smith",
    "profile_id": 2,
    "post_ids": [3, 4]
  }]
}
```

Notice that the root is an array and the root_key a plural. This is the case regardless of whether a single resource
is being represented or a collection of resources. This was at one time in line with the json-api spec (this has since changed) and generally simplifies both serialization and deserialization.

##### Adding Metadata
It might be desirable to add extra metadata to the serialized response. For example, adding information such as limit, offset, what includes are valid etc can be helpful to a client.

`UserSerializer.new(user).meta(limit: 10, offset: 0)`

#### Serializer Groups
As an application grows, it might be necessary to provide multiple representations of the same model for different purposes. This can be achieved by grouping serializers that are intended to work together via the `group` option in the serializer config.

```ruby
class SummaryUserSerializer
  include HttpApiTools::Nesting::JsonSerializer

  serializes(User, group: :summary)

  attributes :id, :first_name, :last_name

  has_many :posts
end
```

```ruby
class SummaryPostSerializer
  include HttpApiTools::Nesting::JsonSerializer

  serializes(User, group: :summary)

  attributes :id, :title

  belongs_to :user
end
```

In this example, when the `SummaryUserSerializer traverses the `posts` relationship, it will use the `SummaryPostSerializer` to serialize posts as both serializers have been configured to belong to the `:summary` group. The group name is not important, and can be any symbol or strong your like to identify the serializer grouping.

When a serializer is configured without an explicit group, the `:default` group is used.


### Deserialization
The `HttpApiTools::JsonDeserializer` expects json in the format that the serializer has created making it easy to create matching rest apis and clients with little work needing to be done at each end. Currently only sideloaded json can be deserialized. Nested deserializers are coming.

`HttpApiTools::JsonDeserializer.new(json).deserialize`

This will iterate over the json, using the attribute names to match types to models in the client app. As long as models exist with names that match the keys in the json, a complete graph of objects will be created upon deserialization, complete with bi-directional relationships when they exist.

In the previous example, the following model classes would be expected:

* User
* Post
* Comment


#### Namespaced Models

At times it might be desirable to namespace your client models. One reason for this might be to differentiate models based on the service or external domain that they are based on. This can also help prevent name clashes between the local application models and remote service models.

For example, a client application that is also a rails application with it's own persistence might have a concept of a `Post` which is also present in the Content Management Service.

So locally your rails model can be called `Post` and your remote `Post` from the CMS can be namespaced as `Cms::Post`.

When deserializing from the CMS service you can select the namespace to deserialize under by defining the namespace in the deserializer:

```ruby
`HttpApiTools::JsonDeserializer.new(json, namespace: Cms).deserialize`
```

#### Deserializer Mappings

At times, the name of an object's key may deviate from it's type and can't be deserialized by convention alone.

```javascript
{
 "users": [{
    "id": 1,
    "first_name": "John",
    "last_name": "Smith",
    "links": {
      "posts": [3]
    }
 }],
 "linked": {
   posts: [
    {
      "id": 3,
      "links": {
        "author": 1
      }
    }
  }
}
```

In this example, the `user` is the `author` of the `post`. It is impossible to infer from the data that an `author` attribute key should map to a `User` type so we need to give it a helping hand. This can be done once per type by creating a `JsonDeserializerMapping` class. Like with serializers, deserializer mappings are convention based, using the model class name as a prefix.

```ruby
class PostDeserializerMapping

  include HttpApiTools::JsonDeserializerMapping

  map :author, User

end
```

Whenever we're deserializing a `post`, the `author` attribute will always be deserialized to an instance of a `User`.

This can also be applied against collections:

```ruby
class CompanyDeserializerMapping

  include HttpApiTools::JsonDeserializerMapping

  map :employees, Person

end
```

### Models
Client models have some basic requirements that are catered to such as attribute definition, default values and type tranforms.

For example:

```ruby
class User

  include HttpApiTools::Model::Attributes
  include HttpApiTools::Model::ActsLikeActiveModel

  attribute :id
  attribute :first_name
  attribute :last_name
  attribute :created_at: type: :date_time

  has_many :posts
  belongs_to :profile

end
```

This will define a User class with attr_accessors for all attributes defined. The initialize method will accept a hash of values which will be passed through type transformers when configured and have defaults applied when no value is passed in for a key.

Currently there is a single registered type transform for date_time transforms. This expects an iso8601 date format as a string which will be transformed into a ruby DateTime.

#### Relationships

`Belongs to` and `has many` relationships should be declared explictly. This will do a couple of things...

* The deserializer will maintain the bi-directional relationship between these models.
* Active Record style attribute accessors for the id representations of the relationships will be made available and maintained.

For example, adding the `has_many :posts` declaration to a class will automcatically create the following methods:

* `posts=` - for setting the collection of posts
* `posts` - for getting the collection of posts
* `post_ids=` - for setting the ids of the posts
* `post_ids` - for gettings the ids of the posts

Any modification to the `posts` attribute will immediately be reflected in the post_ids attribute. This includes replacing it's contents, or manipulating the underlying array by adding or removing items.


#### Registering custom type transformers.

Type transformers expect the following two-way interface:

```ruby
class MoneyTranformer

  def self.from_raw(value)
    Money.new(value)
  end

  def self.to_raw(money)
    money.to_s
  end

end
```

Transformers should then be registered against a type key:


```ruby
HttpApiTools::Transformers::Registry.instance.register(:money, MoneyTransformer)
```

Now you can define an attribute as a `money` type:

```ruby
class Account

  include HttpApiTools::Model::Attributes

  attribute :balance: type: :money

end
```

#### Read only attributes
Sometimes it's useful to define a field as readonly. The intent being that we prevent changing an attribute value that shouldn't be changed or prevent a value from being serialized and sent in the payload that the server won't accept.

In the previous example, it might be better to set the `created_at` field as readonly:

```ruby
class User

  include HttpApiTools::Model::Attributes
  include HttpApiTools::Model::ActsLikeActiveModel

  attribute :id
  attribute :first_name
  attribute :last_name
  attribute :created_at: type: :date_time, read_only: true
  has_many :posts
  belongs_to :profile

end
```

### Polymorphism
At this point, polymorphic relationships are not catered for but they can be when the need arises.


## Contributing

### A note on performance
Performance is critial for this gem so any changes must be made with this in mind. There is a basic performance
spec for serialization that dumps some timings and creates a profile report in `reports/profile_report.html`.

Until we have a more robust way of tracking performance over time, please do some before and after tests against this when you make changes. Even small things have been found to introduce big performance issues.


## To Do
* Deserializer for nested json




