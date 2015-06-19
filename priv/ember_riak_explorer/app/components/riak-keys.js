import Ember from 'ember';

export default Ember.Component.extend({
    actions: {
        deleteObject: function(cluster_id, bucket_type_id, bucket_id, object_key) {
            // Send the 'deleteObject' action to parent controller (key-list)
            this.sendAction('deleteObject', cluster_id, bucket_type_id, bucket_id, object_key);
        }
    }
});