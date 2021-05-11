{application, encd,
 [{description, "Erlang Netchannel Server"},
  {vsn, "1"},
  {modules, [channel, client, encd, nchan, ns, server]},
  {registered, [encd]},
  {applications, [kernel, stdlib]},
  {mod, {encd, []}}
 ]}.
