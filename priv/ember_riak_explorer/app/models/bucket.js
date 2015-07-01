import DS from 'ember-data';

export default DS.Model.extend({
    name: DS.attr('string'),
    cluster: DS.belongsTo('cluster'),
    clusterId: DS.attr(),
    bucketTypeId: DS.attr(),

    bucketId: function() {
        return this.get('name');
    }.property('name')
});
