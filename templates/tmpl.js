function setup_blocks() {
  all_divs = document.getElementsByTagName("div");
  for (var i = 0; i < all_divs.length; i++) {
    if (all_divs[i].className == "blocklink") {
      all_divs[i].style.display = "inline";
      all_divs[i].addEventListener('click', function() { block_visible( this.id.substr(5) ); });
    } else if (all_divs[i].className == "abstract") {
      all_divs[i].style.display = "none";
      all_divs[i].style.position = "absolute";
      all_divs[i].style.left = "60px";
      all_divs[i].style.zIndex = 1;
      all_divs[i].style.border = "#000 1px solid";
      all_divs[i].style.width = "50%";
    }
  }
  var abstract_mask = document.getElementById("abstract_mask");
  if (abstract_mask) {
    var height = Math.max(document.body.scrollHeight, document.body.offsetHeight);
    abstract_mask.style.height=height+"px";
    abstract_mask.addEventListener('click', function() { block_visible(visible_block); });
  }
}
function block_visible(id) {
  if (visible_block) {
    t = document.getElementById(visible_block).style.display = "none";
    var abstract_mask = document.getElementById("abstract_mask");
    if (abstract_mask) {
      abstract_mask.style.display = "none";
    }
    if (visible_block == id) {
      visible_block = 0;
      return;
    }
    visible_block = 0;
  }
  var e = document.getElementById(id);
  if (e) {
     document.getElementById('abstract_mask').style.display="block";
     e.style.display = "block";
     visible_block = id;
  }
}

var visible_block = 0;
setup_blocks();
