import DS from 'ember-data';

var RiakObject = DS.Model.extend({

    bucket: DS.belongsTo('bucket'),

    bucketType: DS.belongsTo('bucket-type'),

    cluster: DS.belongsTo('cluster'),

    contents: DS.attr(),

    headers: DS.attr(),

    isLoaded: DS.attr('boolean', {defaultValue: false}),

    key: DS.attr('string'),

    // This object was marked as deleted by Explorer UI,
    //  but may show up in key list cache.
    markedDeleted: DS.attr('boolean', {defaultValue: false}),

    rawUrl: DS.attr('string'),

    bucketId: function() {
        return this.get('bucket').get('bucketId');
    }.property('bucket'),

    bucketTypeId: function() {
        return this.get('bucketType').get('bucketTypeId');
    }.property('bucket'),

    causalContext: function() {
        return this.get('headers').other['x-riak-vclock'];
    }.property('headers'),

    clusterId: function() {
        return this.get('cluster').get('clusterId');
    }.property('bucket'),

    contentType: function() {
        return this.get('headers').other['content-type'];
    }.property('headers'),

    dateLastModified: function() {
        return this.get('headers').other['last-modified'];
    }.property('headers'),

    // When this object was loaded from Riak via an HTTP request
    dateLoaded: function() {
        return this.get('headers').other['date'];
    }.property('headers'),

    etag: function() {
        return this.get('headers').other['etag'];
    }.property('headers'),

    headersCustom: function() {
        return this.get('headers').custom;
    }.property('headers'),

    /**
    * Return the necessary headers when saving an object via HTTP PUT
    */
    headersForUpdate: function() {
        // Start with the causal context
        var headers = {
            'X-Riak-Vclock': this.get('headers').other['x-riak-vclock']
        };
        var header;
        var i;
        // Add the 2i indexes, if applicable
        var indexes = this.get('headersIndexes');
        for (i = 0; i < indexes.length; i++) {
            header = indexes[i];
            headers[header.key] = header.value;
        }
        // Add the user-defined custom headers
        var customHeaders = this.get('headersCustom');
        for (i = 0; i < customHeaders.length; i++) {
            header = customHeaders[i];
            headers[header.key] = header.value;
        }
        return headers;
    }.property('headers'),

    headersIndexes: function() {
        return this.get('headers').indexes;
    }.property('headers'),

    isDeleted: function() {
        var deletedOnRiak = false;
        if(this.get('headers')) {
            deletedOnRiak = this.get('headers').other['x-riak-deleted'];
        }
        return this.get('markedDeleted') || deletedOnRiak;
    }.property('markedDeleted', 'headers')
});

export default RiakObject;
