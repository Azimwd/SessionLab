"""Place new player characters in the campaign's shared Players folder."""

from django.db.models.signals import post_save, pre_save
from django.dispatch import receiver

from .models import Campaign, Character, CharacterFolder


def players_folder(campaign):
    folder = CharacterFolder.objects.filter(campaign=campaign, is_system=True).first()
    if folder:
        return folder
    folder = CharacterFolder.objects.filter(
        campaign=campaign, owner_id=campaign.owner_id, name='Игроки'
    ).first()
    if folder:
        folder.is_system = True
        folder.visible_to_players = True
        folder.save(update_fields=['is_system', 'visible_to_players', 'updated_at'])
        return folder
    return CharacterFolder.objects.create(
        campaign=campaign, owner_id=campaign.owner_id, name='Игроки',
        is_system=True, visible_to_players=True,
    )


@receiver(post_save, sender=Campaign)
def create_players_folder(sender, instance, created, **kwargs):
    if created:
        players_folder(instance)


@receiver(pre_save, sender=Character)
def assign_new_player_to_folder(sender, instance, **kwargs):
    if instance._state.adding and instance.kind == 'player' and instance.folder_id is None:
        instance.folder = players_folder(instance.campaign)
