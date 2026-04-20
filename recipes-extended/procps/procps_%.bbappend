# Disabilita il supporto systemd-logind in procps.                                                                                                                                    
# Motivazione: su procps-ng 4.0.4 con --with-systemd, il comando `w`                                                                                                                  
# confronta CLOCK_MONOTONIC (IdleSinceHintMonotonic) con CLOCK_REALTIME                                                                                                               
# (time(NULL)), producendo IDLE ~20562 giorni e TTY vuoto per ogni                                                                                                                    
# sessione. Disabilitando systemd, `w` torna a leggere /var/run/utmp                                                                                                                  
# come `who`. Rimuovere quando procps sarà bumpato a >= 4.0.5.                                                                                                                        
PACKAGECONFIG:remove = "systemd"            
