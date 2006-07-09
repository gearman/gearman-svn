Contents:

Gearman               --- client/worker/util libraries for speaking the Gearman protocol
                          from Perl.  no async versions, though.  (although the Gearman::Client
                          taskset interface has its own mini event loop for doing things in
                          parallel)

Gearman-DangaSocket   --- async versions which fit into the Danga::Socket world.
                          depends on the base Gearman stuff.
