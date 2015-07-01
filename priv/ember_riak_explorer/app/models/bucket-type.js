import DS from 'ember-data';
import objectToArray from '../utils/riak-util';

export default DS.Model.extend({
    name: DS.attr('string'),
    cluster: DS.attr(),

    // {"allow_mult":false, "basic_quorum":false, ... }
    props: DS.attr(),

    bucketTypeId: function() {
        return this.get('name');
    }.property('name'),

    propsList: function() {
        return objectToArray(this.get('props'));
    }.property('props')
});
