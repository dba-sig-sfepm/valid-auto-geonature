# Valid-Auto-Geonature

Moteur de validation automatique des données de l'ONM (Observatoire National des Mammifères) de la SFEPM

<img src="https://ressources.observatoire-mammiferes.fr/files/asset/c4c8df9fd8924f334984966317889c14612d702c.png" alt="Logo ONM / SFEPM" width="800">

L'ONM centralise à l'échelle nationale les données d'observations de mammifères (Métropole et Outre-mer). La gestion des données s'appuie sur l'application [GeoNature](https://github.com/PnX-SI/GeoNature).   
L'ONM a également en charge la validation de l'ensemble des données selon le [guide méthodologique](https://observatoire-mammiferes.fr/static/docs/ONM_Validation_Guide%20methodologique.pdf).

Ce dépot décrit le moteur PostgreSQL développé pour la validation automatique des observations. Il est constitué d'une [notice technique](/Notice%20technique%20-%20Validation%20automatique%20ONM.pdf) ainsi que les codes des différentes focnctions utilisées.
Ce moteur de validation est distinct de GeoNature cependant il puise les données dans certaines tables de GeoNature comme la synthese et utilise certaines fonctionnalités comme les listes taxonomiques
