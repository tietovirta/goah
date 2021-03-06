$(document).ready(function(){
	
// Add datepicker to date inputs. For more information and localizations 
// visit to http://http://keith-wood.name/datepick.html
	$('.date').datepick();	
	
// Show and hide tablet-navigation
	jQuery( function( $ ) {
		$('#navi-tablet').hide();
		$( '.toggle-navi' ).click( function() {
			$('#navi-tablet').slideToggle( 'fast' );
			return false;
    	} );
    } );

// Toggle subnavi. Close previous and add class active to selected menu item.
	jQuery( function( $ ) {
		$( '.nav-toggle-next:not(#active) + *' ).hide();
		$( '.nav-toggle-next' ).click( function() {
			$('li').removeAttr("id");
			$( this ).attr("id","active");
			$( this ).next().slideToggle( 'fast' );
			$( '.nav-toggle-next:not(#active) + *' ).hide();			
			return false;
    	} );
    } );
    
/* Toggle next tr which is after <tr class="toggle-next-tr">. Default action is set to hide following tr.
	Action is tied to first cell of class=toggle-next-tr.

	NOTE: Add colspan to hided tr => td and class <td class="show-hidden". Also, if you want to toggle values + and -
	then add + sign to <td class="show-hidden">+</td>, or edit below to match you desires.
*/ 
	jQuery( function( $ ) {
		$( '.toggle-next-tr + *' ).hide();
		$( '.toggle-next-tr td:first-child' ).click( function() {	
			$( this ).parent().next().slideToggle( 'fast' );
			var text = $(this).text() == '-' ? '+' : '-';
   		$(this)
   		.text(text)
   		.toggleClass("active");
			return false;
    	} );
    } );

    
});