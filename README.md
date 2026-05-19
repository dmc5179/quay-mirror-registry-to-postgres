# Script to convert quay mirror registry database from sqlite to postgres

- Based on this access article:
https://access.redhat.com/solutions/7140667

- Note that once this process is complete, you will need to browse to the web console of the quay registry and recreate a user as there are no users
  Can just add back the default init with the random password
