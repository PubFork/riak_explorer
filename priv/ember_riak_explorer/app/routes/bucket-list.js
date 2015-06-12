import Ember from 'ember';

export default Ember.Route.extend({
    queryParams: {
        cluster_id: {
            refreshModel: true
        },
        bucket_type_id: {
            refreshModel: true
        }
    },

    model: function(params) {
        var url = '/explore/clusters/' + params.cluster_id +
            '/bucket_types/' + params.bucket_type_id + '/buckets' ;

        var result = Ember.$.ajax( url, { dataType: "json" } );
        return result.then(
            function(data) {
                return {
                    cluster_id: params.cluster_id,
                    bucket_type_id: params.bucket_type_id,
                    bucket_list: data.buckets
                };
            }
        );
    }
});
