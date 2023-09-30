tags=( "v2.0.0-rc1" "v2.0.0-rc10" "v2.0.0-rc11" "v2.0.0-rc12" "v2.0.0-rc2" "v2.0.0-rc3" "v2.0.0-rc4" "v2.0.0-rc5" "v2.0.0-rc6" "v2.0.0-rc7" "v2.0.0-rc8" "v2.0.0-rc9" ) 

for i in ${!tags[@]};
do
  tag=${tags[$i]}
  git tag -d ${tag}
  git push --delete origin ${tag}
done