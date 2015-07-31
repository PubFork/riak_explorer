import Ember from 'ember';

export default Ember.Controller.extend({
    explorer: Ember.inject.service('explorer'),

    queryParams: ['cluster_id', 'bucket_type_id'],
    cluster_id: null,
    bucket_type_id: null,

    actions: {
        deleteBucket: function(bucket) {
            this.get('explorer').deleteBucket(bucket);
            // this.get('explorer').markDeletedBucket(bucket);

            // Once the delete has been issued,
            // return to the bucket type's Bucket List view.
            this.transitionToRoute('bucket_list',
                { queryParams: {
                    cluster_id: bucket.get('clusterId'),
                    bucket_type_id: bucket.get('bucketTypeId')
                }});
        },
        refreshBuckets: function(bucketList) {
            var cluster = bucketList.get('cluster');
            var clusterId = cluster.get('clusterId');
            var bucketTypeId = bucketList.get('bucketTypeId');

            this.get('explorer').bucketCacheRefresh(clusterId, bucketTypeId);

            this.transitionToRoute('bucket_list',
                { queryParams: {
                    cluster_id: bucketList.get('cluster').get('clusterId'),
                    bucket_type_id: bucketList.get('bucketTypeId')
                }});
        }
    }
});
